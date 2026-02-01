from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
from typing import Any, cast

import anyio

from takopi.api import (
    CommandContext,
    CommandResult,
    MessageRef,
    RunContext,
    RunningTask,
    RunningTasks,
)

from takopi_dotfiles.worktree import resolve_run_cwd_with_retry


def _decode_output(data: bytes) -> str:
    try:
        return data.decode("utf-8", errors="replace")
    except Exception:
        return repr(data)

def _extract_session_id(text: str) -> str | None:
    if not text:
        return None
    match = re.search(r"\bses_[A-Za-z0-9]+\b", text)
    if match is None:
        return None
    return match.group(0)


def _opencode_data_dir() -> Path:
    raw = os.environ.get("XDG_DATA_HOME", "")
    if raw:
        return Path(raw)
    return Path.home() / ".local" / "share"


def _opencode_session_file(session_id: str) -> Path | None:
    if not session_id:
        return None
    sessions_dir = _opencode_data_dir() / "opencode" / "storage" / "session"
    if not sessions_dir.is_dir():
        return None
    matches = list(sessions_dir.glob(f"**/{session_id}.json"))
    if not matches:
        return None
    return matches[0]


def _opencode_session_directory(session_id: str) -> Path | None:
    session_file = _opencode_session_file(session_id)
    if session_file is None:
        return None

    try:
        payload = json.loads(session_file.read_text(encoding="utf-8"))
    except Exception:
        return None

    directory = payload.get("directory") or ""
    if isinstance(directory, str) and directory:
        path = Path(directory)
        if path.is_dir():
            return path
    return None


def _is_disposable_worktree_path(path: Path) -> bool:
    value = str(path)
    return "/.opencode/worktrees/" in value or "/.worktrees/" in value


async def _latest_disposable_worktree(repo_root: Path) -> tuple[Path, str] | None:
    result = await anyio.run_process(
        ["git", "-C", str(repo_root), "worktree", "list", "--porcelain"],
        check=False,
    )
    if result.returncode != 0:
        return None

    entries: list[tuple[Path, str]] = []
    worktree_path: Path | None = None
    branch = ""

    for raw_line in _decode_output(result.stdout).splitlines():
        line = raw_line.strip()
        if not line:
            if worktree_path is not None and branch:
                entries.append((worktree_path, branch))
            worktree_path = None
            branch = ""
            continue

        if line.startswith("worktree "):
            worktree_path = Path(line.split(" ", 1)[1].strip())
            branch = ""
            continue

        if line.startswith("branch "):
            branch_ref = line.split(" ", 1)[1].strip()
            if branch_ref.startswith("refs/heads/"):
                branch = branch_ref.removeprefix("refs/heads/")
            else:
                branch = branch_ref

    if worktree_path is not None and branch:
        entries.append((worktree_path, branch))

    candidates: list[tuple[float, Path, str]] = []
    for path, branch in entries:
        if not _is_disposable_worktree_path(path):
            continue
        if not path.is_dir():
            continue
        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue
        candidates.append((mtime, path, branch))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[0], reverse=True)
    _, path, branch = candidates[0]
    return path, branch


def _select_cancel_target(
    ctx: CommandContext,
    *,
    running_tasks: RunningTasks,
    resolved_context: Any,
) -> tuple[MessageRef, RunningTask] | None:
    if ctx.reply_to is not None:
        task = running_tasks.get(ctx.reply_to)
        if task is not None:
            return ctx.reply_to, task

    if resolved_context is None:
        return None

    candidates: list[tuple[MessageRef, RunningTask]] = []
    for ref, task in running_tasks.items():
        if ref.channel_id != ctx.message.channel_id:
            continue
        if task.context != resolved_context:
            continue
        candidates.append((ref, task))

    if len(candidates) == 1:
        return candidates[0]

    return None


@dataclass(slots=True)
class FinishCommand:
    id: str = "finish"
    description: str = "cancel run and start PR auto-merge"

    async def handle(self, ctx: CommandContext) -> CommandResult | None:
        args_text = ctx.args_text.strip()
        resolved = ctx.runtime.resolve_message(
            text=args_text,
            reply_text=ctx.reply_text,
            chat_id=cast(int, ctx.message.channel_id),
        )

        selected_detail = ""

        session_id = _extract_session_id(f"{args_text}\n{ctx.reply_text or ''}")
        run_cwd = _opencode_session_directory(session_id) if session_id else None

        if run_cwd is None:
            if resolved.context is not None:
                try:
                    run_cwd = await resolve_run_cwd_with_retry(ctx, resolved.context)
                except Exception as exc:
                    message = str(exc).strip() or exc.__class__.__name__
                    return CommandResult(
                        text=(
                            "Worktree lookup failed.\n\n"
                            f"{message}\n\n"
                            "Tip: wait a few seconds and try again. If it persists, restart the Takopi launch agent."
                        )
                    )
        if run_cwd is None:
            return CommandResult(
                text=(
                    "I can't tell which repo/worktree to finish.\n\n"
                    "Use one of:\n"
                    "- reply to a takopi message with `/finish`\n"
                    "- `/finish /<project> @<branch>`"
                )
            )

        context_branch = getattr(resolved.context, "branch", None) if resolved.context is not None else None
        explicit_branch = isinstance(context_branch, str) and context_branch.strip()
        context_project = getattr(resolved.context, "project", None) if resolved.context is not None else None
        project_key = context_project.lower() if isinstance(context_project, str) and context_project else ""

        if not explicit_branch and project_key:
            project_root = ctx.runtime.resolve_run_cwd(RunContext(project=project_key))
            if project_root is not None and project_root == run_cwd:
                latest = await _latest_disposable_worktree(project_root)
                if latest is not None:
                    run_cwd, inferred_branch = latest
                    selected_detail = f"finish: inferred worktree `{project_key}` @ `{inferred_branch}`"

        cancelled = False
        cancel_detail = ""

        running_tasks_raw = getattr(ctx.executor, "_running_tasks", None)
        if isinstance(running_tasks_raw, dict):
            running_tasks = cast(RunningTasks, running_tasks_raw)
            target = _select_cancel_target(
                ctx,
                running_tasks=running_tasks,
                resolved_context=resolved.context,
            )
            if target is not None:
                ref, running_task = target
                running_task.cancel_requested.set()
                cancelled = True
                cancel_timeout_s = int(ctx.plugin_config.get("cancel_timeout_s", 60))
                try:
                    with anyio.fail_after(cancel_timeout_s):
                        await running_task.done.wait()
                except TimeoutError:
                    cancel_detail = (
                        f"(timed out after {cancel_timeout_s}s; continuing anyway)"
                    )
                else:
                    cancel_detail = f"(cancelled run from message {ref.message_id})"

        script = Path.home() / ".config" / "opencode" / "completion-workflow-start.sh"
        if not script.exists():
            return CommandResult(
                text=f"Missing script: {script}\nExpected from ~/dotfiles/opencode/.",
            )

        result = await anyio.run_process(
            ["bash", str(script), "--repo", str(run_cwd)],
            cwd=str(run_cwd),
            check=False,
        )

        stdout = _decode_output(result.stdout).strip()
        stderr = _decode_output(result.stderr).strip()

        log_path = ""
        for line in reversed(stdout.splitlines()):
            line = line.strip()
            if line:
                log_path = line
                break

        lines: list[str] = []
        if selected_detail:
            lines.append(selected_detail)
        lines.append(f"finish: started completion workflow in {run_cwd}")
        if cancelled:
            lines.append(f"finish: cancel requested {cancel_detail}".rstrip())
        if result.returncode != 0:
            lines.append(f"finish: workflow start failed (exit {result.returncode})")
            if stdout:
                lines.append("")
                lines.append("stdout:")
                lines.append(stdout[-3000:])
            if stderr:
                lines.append("")
                lines.append("stderr:")
                lines.append(stderr[-3000:])
            return CommandResult(text="\n".join(lines))

        if log_path:
            lines.append(f"log: {log_path}")
            lines.append("tip: enable takopi files, then `/file get <log>` to fetch it.")
        elif stdout:
            lines.append("finish: workflow started, but couldn't parse log path.")
            lines.append("")
            lines.append(stdout[-3000:])

        return CommandResult(text="\n".join(lines))


BACKEND = FinishCommand()
