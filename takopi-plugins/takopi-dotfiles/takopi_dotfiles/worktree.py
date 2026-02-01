from __future__ import annotations

from pathlib import Path

import anyio

from takopi.api import CommandContext, RunContext


_WORKTREE_LOCK = anyio.Lock()


def _is_transient_worktree_error(exc: BaseException) -> bool:
    message = str(exc)
    return "cannot fork()" in message or "Resource temporarily unavailable" in message


async def resolve_run_cwd_with_retry(
    ctx: CommandContext,
    run_ctx: RunContext,
    *,
    attempts: int = 4,
    initial_delay_s: float = 0.25,
) -> Path | None:
    async with _WORKTREE_LOCK:
        delay_s = initial_delay_s
        for attempt in range(attempts):
            try:
                cwd = ctx.runtime.resolve_run_cwd(run_ctx)
                if cwd is not None:
                    return cwd
            except Exception as exc:
                if attempt < attempts - 1 and _is_transient_worktree_error(exc):
                    await anyio.sleep(delay_s)
                    delay_s = min(delay_s * 2, 3.0)
                    continue
                raise

            if attempt < attempts - 1:
                await anyio.sleep(0)

        return None
