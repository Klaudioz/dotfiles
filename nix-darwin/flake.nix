{
  description = "My Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
  let
    configuration = { pkgs, ... }:
    let
      ocxVersion = "1.2.2";
      ocxAsset =
        if pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64 then {
          name = "ocx-darwin-arm64";
          hash = "sha256-QH3DTgmC0JxjpDf/DkyFW5Op7AvP//omNzH9mVU0/Vo=";
        } else if pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isx86_64 then {
          name = "ocx-darwin-x64";
          hash = "sha256-880yw6Ro9euwWfnMeBhAe8DFB+zyBx4ciI98I5FnR0Y=";
        } else
          throw "ocx is only packaged for macOS in this flake";

      ocxSrc = pkgs.fetchurl {
        url = "https://github.com/kdcokenny/ocx/releases/download/v${ocxVersion}/${ocxAsset.name}";
        hash = ocxAsset.hash;
      };

      ocx = pkgs.stdenvNoCC.mkDerivation {
        pname = "ocx";
        version = ocxVersion;
        src = ocxSrc;
        dontUnpack = true;

        installPhase = ''
          install -Dm755 "$src" "$out/bin/ocx"
        '';

        meta = with pkgs.lib; {
          description = "Package manager for OpenCode extensions";
          homepage = "https://github.com/kdcokenny/ocx";
          license = licenses.mit;
          platforms = platforms.darwin;
        };
      };

      # Amp CLI from ampcode.com
      ampVersion = "0.0.1769531025-g50c6da";
      ampAsset =
        if pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64 then {
          name = "amp-darwin-arm64";
          hash = "sha256-UL0xeSLAZd+AIfxl1wP9HHVEXWOZNuDE0/jyQBEXOx4=";
        } else if pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isx86_64 then {
          name = "amp-darwin-x64";
          hash = "sha256-guCT5xkdK+l51TbT4E/XLddpF8oONAvuO9bF6ICLYv4=";
        } else
          throw "amp is only packaged for macOS in this flake";

      ampSrc = pkgs.fetchurl {
        url = "https://storage.googleapis.com/amp-public-assets-prod-0/cli/${ampVersion}/${ampAsset.name}";
        hash = ampAsset.hash;
      };

      amp = pkgs.stdenvNoCC.mkDerivation {
        pname = "amp";
        version = ampVersion;
        src = ampSrc;
        dontUnpack = true;

        installPhase = ''
          install -Dm755 "$src" "$out/bin/amp"
        '';

        meta = with pkgs.lib; {
          description = "Amp CLI - AI coding assistant from ampcode.com";
          homepage = "https://ampcode.com";
          platforms = platforms.darwin;
        };
      };

      tomd = pkgs.python3Packages.buildPythonPackage rec {
        pname = "tomd";
        version = "0.1.3";
        pyproject = true;
        build-system = with pkgs.python3Packages; [
          setuptools
        ];
        src = pkgs.fetchPypi {
          inherit pname version;
          hash = "sha256-I/Ia6FMVe+SdFjFZvHxrwAfdXoe2l2nsW6Phf13nptQ=";
        };
        doCheck = false;
      };

      webdriver-manager = pkgs.python3Packages.buildPythonPackage rec {
        pname = "webdriver-manager";
        version = "4.0.2";
        pyproject = true;
        build-system = with pkgs.python3Packages; [
          setuptools
        ];
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/source/w/webdriver-manager/webdriver_manager-4.0.2.tar.gz";
          hash = "sha256-7+30KPkv1tXJJKDQVObRMi3Xeqt5DoNO52evOSs1WQ8=";
        };
        propagatedBuildInputs = with pkgs.python3Packages; [
          requests
          python-dotenv
          packaging
        ];
        doCheck = false;
      };

      datacamp-downloader = pkgs.python3Packages.buildPythonPackage rec {
        pname = "datacamp-downloader";
        version = "3.3";
        pyproject = true;
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/source/d/datacamp-downloader/datacamp_downloader-3.3.tar.gz";
          hash = "sha256-VLn6kvz/Ry7KEKuHnPjyGfTYZMx8e3WISHpRWtwWrXg=";
        };
        nativeBuildInputs = with pkgs.python3Packages; [
          setuptools
          wheel
          setuptools-git
          pythonRelaxDepsHook
        ];
        pythonRelaxDeps = [
          "beautifulsoup4"
          "selenium"
          "undetected-chromedriver"
          "texttable"
          "termcolor"
          "colorama"
          "typer"
          "setuptools"
        ];
        postPatch = ''
python - <<'PY'
from pathlib import Path
path = Path("src/datacamp_downloader/session.py")
text = path.read_text()
old = 'profile_dir = os.path.join(package_dir, "dc_chrome_profile")'
new = 'cache_root = os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))\n        profile_dir = os.path.join(cache_root, "datacamp-downloader", "dc_chrome_profile")'
if old not in text:
    raise SystemExit("profile_dir line not found for patching")
path.write_text(text.replace(old, new))

text = path.read_text()
old_block = """        service = ChromeService(executable_path=ChromeDriverManager().install())
        try:
            self.driver = uc.Chrome(service=service, options=options)
            return
        except Exception:
            self.driver = webdriver.Chrome(service=service, options=options)
"""
new_block = """        options.add_argument("--remote-debugging-port=0")
        options.add_argument("--remote-allow-origins=*")

        service = ChromeService()
        try:
            self.driver = webdriver.Chrome(service=service, options=options)
            return
        except Exception:
            try:
                self.driver = uc.Chrome(options=options)
                return
            except Exception:
                self.driver = webdriver.Chrome(service=service, options=options)
"""
if old_block not in text:
    raise SystemExit("driver block not found for patching")
path.write_text(text.replace(old_block, new_block))

text = path.read_text()
old_get_json = """    def get_json(self, url):
        page = self.get(url).strip()

        # Parse with BeautifulSoup
        soup = BeautifulSoup(page, "html.parser")
        pre = soup.find("pre")

        if pre:
            page = pre.text  # ✅ grab only the JSON inside <pre>
        else:
            page = page  # maybe raw JSON already

        # Debug
        #print("\\n\\n[DEBUG get_json cleaned] First 200 chars:\\n", page[:200], "\\n\\n")

        return json.loads(page)
"""
js = (
    "const url = arguments[0]; const callback = arguments[1];"
    "fetch(url, {credentials: \\\"include\\\"})"
    ".then(r => r.text()).then(t => callback(t)).catch(e => callback(\\\"\\\"));"
)
new_get_json = f"""    def get_json(self, url):
        page = self.get(url).strip()

        if "<html" in page.lower():
            for _ in range(30):
                if "just a moment" not in page.lower() and "cloudflare" not in page.lower():
                    break
                self.driver.get(url)
                self.bypass_cloudflare(url)
                page = self.driver.page_source.strip()

            if "<html" in page.lower():
                try:
                    page = self.driver.execute_async_script(
                        {js!r},
                        url,
                    ).strip()
                except Exception:
                    pass

        soup = BeautifulSoup(page, "html.parser")
        pre = soup.find("pre")

        if pre:
            page = pre.text
        else:
            page = page

        return json.loads(page)
"""
if old_get_json not in text:
    raise SystemExit("get_json block not found for patching")
path.write_text(text.replace(old_get_json, new_get_json))
PY

python - <<'PY'
from pathlib import Path
import re

utils = Path("src/datacamp_downloader/datacamp_utils.py")
text = utils.read_text()
m = re.search(r"^([ \\t]*)def list_completed_tracks", text, re.M)
if not m:
    raise SystemExit("list_completed_tracks block not found for patching")
indent = m.group(1)

renderer = Path("src/datacamp_downloader/projector_mp4.py")
renderer.write_text(
    """from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from selenium.webdriver.common.by import By

from .helper import Logger

PROJECTOR_URL = "https://projector.datacamp.com/?projector_key={key}"


def _ffprobe_duration(path: Path) -> float:
    proc = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout).strip()
        raise RuntimeError(f"ffprobe failed: {msg}")
    return float(proc.stdout.strip())


def _parse_segments(timings_data, audio_duration: float):
    if not timings_data:
        timings = []
    elif isinstance(timings_data, str):
        try:
            timings = json.loads(timings_data)
        except Exception:
            timings = []
    elif isinstance(timings_data, (list, tuple)):
        timings = list(timings_data)
    else:
        timings = []
    events = []
    for item in timings:
        try:
            t = float(item.get("timing"))
            state = item.get("state") or {}
            h = int(state.get("indexh"))
            f = int(state.get("indexf", -1))
        except Exception:
            continue
        events.append((t, h, f))

    if not events:
        return []

    events.sort(key=lambda x: x[0])
    max_t = max(t for t, _, _ in events)

    # Most projector timings are normalized to [0, 1].
    if max_t <= 1.5:
        events = [
            (max(0.0, min(audio_duration, t * audio_duration)), h, f)
            for t, h, f in events
        ]
    else:
        events = [(max(0.0, min(audio_duration, t)), h, f) for t, h, f in events]

    compressed = []
    for t, h, f in events:
        if not compressed or (h, f) != (compressed[-1][1], compressed[-1][2]):
            compressed.append((t, h, f))

    if compressed and compressed[0][0] > 0:
        compressed.insert(0, (0.0, compressed[0][1], compressed[0][2]))

    segments = []
    for i, (start, h, f) in enumerate(compressed):
        end = compressed[i + 1][0] if i + 1 < len(compressed) else audio_duration
        if end <= start:
            continue
        if (end - start) < 0.05:
            continue
        segments.append((start, end, h, f))
    return segments


def render_projector_mp4(
    driver,
    projector_key: str,
    timings_json: str,
    audio_path: Path,
    out_mp4: Path,
    overwrite: bool = False,
):
    out_mp4 = Path(out_mp4)
    audio_path = Path(audio_path)

    if out_mp4.exists() and not overwrite:
        Logger.warning(f"{out_mp4.absolute()} is already downloaded")
        return out_mp4

    duration = _ffprobe_duration(audio_path)
    tmpdir = Path(tempfile.mkdtemp(prefix="datacamp-projector-"))
    try:
        url = PROJECTOR_URL.format(key=projector_key)
        driver.get(url)

        for _ in range(200):
            ready = driver.execute_script(
                "return !!window.Reveal && typeof window.Reveal.slide === 'function'"
            )
            if ready:
                break
            time.sleep(0.1)

        slides_el = driver.find_element(By.CSS_SELECTOR, ".slides")

        segments = _parse_segments(timings_json, duration)
        if not segments:
            timings_from_page = None
            js = (
                "const el =\\n"
                "  document.getElementById('slideDeckData') ||\\n"
                "  document.querySelector('input#slideDeckData') ||\\n"
                "  document.querySelector('input[name=slideDeckData]');\\n"
                "if (!el) return null;\\n"
                "const raw = el.value || el.getAttribute('value') || el.textContent;\\n"
                "if (!raw) return null;\\n"
                "try {\\n"
                "  const obj = JSON.parse(raw);\\n"
                "  const t =\\n"
                "    obj.timings ||\\n"
                "    (obj.slideDeck && obj.slideDeck.timings) ||\\n"
                "    (obj.slide_deck && obj.slide_deck.timings);\\n"
                "  return t || null;\\n"
                "} catch (e) {\\n"
                "  return raw;\\n"
                "}\\n"
            )
            for _ in range(50):
                try:
                    timings_from_page = driver.execute_script(js)
                except Exception:
                    timings_from_page = None
                if timings_from_page:
                    break
                time.sleep(0.1)
            segments = _parse_segments(timings_from_page, duration)

        if not segments:
            Logger.warning("No timings found; rendering a static slide video.")
            segments = [(0.0, duration, 0, -1)]

        frames = []
        for idx, (_, end, h, f) in enumerate(segments, 1):
            driver.execute_script(
                "window.Reveal.slide(arguments[0], 0, arguments[1])", h, f
            )
            time.sleep(0.1)
            frame_path = tmpdir / f"frame_{idx:04d}.png"
            slides_el.screenshot(str(frame_path))
            frames.append((frame_path, float(end)))

        concat = tmpdir / "frames.txt"
        lines = []
        for i, (frame, end) in enumerate(frames):
            start = segments[i][0]
            dur = max(0.05, end - start)
            lines.append(f"file {frame}")
            lines.append(f"duration {dur:.6f}")
        if frames:
            lines.append(f"file {frames[-1][0]}")
        concat.write_text("\\n".join(lines) + "\\n", encoding="utf-8")

        out_mp4.parent.mkdir(parents=True, exist_ok=True)

        cmd = [
            "ffmpeg",
            "-y" if overwrite else "-n",
            "-loglevel",
            "error",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat),
            "-i",
            str(audio_path),
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-shortest",
            "-movflags",
            "+faststart",
            str(out_mp4),
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            msg = (proc.stderr or proc.stdout).strip()
            raise RuntimeError(f"ffmpeg failed: {msg}")

        return out_mp4
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
""",
    encoding="utf-8",
)

method = (
    f"\n{indent}@try_except_request\n"
    f"{indent}def resolve_course_id(self, value: str):\n"
    f"{indent}    if value.isnumeric():\n"
    f"{indent}        return int(value)\n\n"
    f"{indent}    slug = value\n"
    f"{indent}    if value.startswith(\"http\") and \"/learn/courses/\" in value:\n"
    f"{indent}        slug = value.split(\"/learn/courses/\")[1].split(\"?\")[0].strip(\"/\")\n"
    f"{indent}    slug = slug.strip(\"/\")\n\n"
    f"{indent}    api = f\"https://learn-hub-api.datacamp.com/courses/v2/{{slug}}\"\n"
    f"{indent}    self.session.start()\n"
    f"{indent}    data = None\n"
    f"{indent}    try:\n"
    f"{indent}        import requests as _requests\n"
    f"{indent}        cookies = {{c.get('name'): c.get('value') for c in self.session.driver.get_cookies()}}\n"
    f"{indent}        resp = _requests.get(api, cookies=cookies, timeout=20)\n"
    f"{indent}        if resp.ok:\n"
    f"{indent}            data = resp.json()\n"
    f"{indent}    except Exception:\n"
    f"{indent}        data = None\n\n"
    f"{indent}    if data is None:\n"
    f"{indent}        try:\n"
    f"{indent}            data = self.session.get_json(api)\n"
    f"{indent}        except Exception:\n"
    f"{indent}            data = None\n\n"
    f"{indent}    if isinstance(data, dict):\n"
    f"{indent}        course = data.get(\"course\") or data.get(\"data\", {{}}).get(\"course\")\n"
    f"{indent}        if isinstance(course, dict) and isinstance(course.get(\"id\"), int):\n"
    f"{indent}            return course.get(\"id\")\n\n"
    f"{indent}    if value.startswith(\"http\"):\n"
    f"{indent}        url = value\n"
    f"{indent}    else:\n"
    f"{indent}        url = f\"https://app.datacamp.com/learn/courses/{{slug}}\"\n\n"
    f"{indent}    try:\n"
    f"{indent}        self.session.driver.get(url)\n"
    f"{indent}        self.session.bypass_cloudflare(url)\n"
    f"{indent}        html = self.session.driver.page_source\n"
    f"{indent}    except Exception:\n"
    f"{indent}        html = self.session.get(url)\n\n"
    f"{indent}    if not html:\n"
    f"{indent}        Logger.error(\"Cannot access course page.\")\n"
    f"{indent}        return\n\n"
    f"{indent}    patterns = [\n"
    f"{indent}        r'data-course-id=\"(\\\\d+)\"',\n"
    f"{indent}        r'\"courseId\":(\\\\d+)',\n"
    f"{indent}        r'\"course_id\":(\\\\d+)',\n"
    f"{indent}    ]\n"
    f"{indent}    for pattern in patterns:\n"
    f"{indent}        match = re.search(pattern, html)\n"
    f"{indent}        if match:\n"
    f"{indent}            return int(match.group(1))\n\n"
    f"{indent}    try:\n"
    f"{indent}        import json as _json\n"
    f"{indent}        next_data = None\n"
    f"{indent}        try:\n"
    f"{indent}            next_data = self.session.driver.execute_script(\"return window.__NEXT_DATA__ || null\")\n"
    f"{indent}        except Exception:\n"
    f"{indent}            next_data = None\n"
    f"{indent}        if next_data is None:\n"
    f"{indent}            try:\n"
    f"{indent}                txt = self.session.driver.execute_script(\"const el=document.querySelector('#__NEXT_DATA__'); return el?el.textContent:null\")\n"
    f"{indent}                if txt:\n"
    f"{indent}                    next_data = _json.loads(txt)\n"
    f"{indent}            except Exception:\n"
    f"{indent}                next_data = None\n"
    f"{indent}        apollo = None\n"
    f"{indent}        try:\n"
    f"{indent}            apollo = self.session.driver.execute_script(\"return window.__APOLLO_STATE__ || null\")\n"
    f"{indent}        except Exception:\n"
    f"{indent}            apollo = None\n"
    f"{indent}        def find_id(obj):\n"
    f"{indent}            stack = [obj]\n"
    f"{indent}            while stack:\n"
    f"{indent}                cur = stack.pop()\n"
    f"{indent}                if isinstance(cur, dict):\n"
    f"{indent}                    if cur.get('slug') == slug and isinstance(cur.get('id'), int):\n"
    f"{indent}                        return cur.get('id')\n"
    f"{indent}                    for k, v in cur.items():\n"
    f"{indent}                        if k in (\"courseId\", \"course_id\") and isinstance(v, int):\n"
    f"{indent}                            return v\n"
    f"{indent}                        stack.append(v)\n"
    f"{indent}                elif isinstance(cur, list):\n"
    f"{indent}                    stack.extend(cur)\n"
    f"{indent}            return None\n"
    f"{indent}        for source in (next_data, apollo):\n"
    f"{indent}            if source is None:\n"
    f"{indent}                continue\n"
    f"{indent}            result = find_id(source)\n"
    f"{indent}            if result:\n"
    f"{indent}                return result\n"
    f"{indent}    except Exception:\n"
    f"{indent}        pass\n\n"
    f"{indent}    Logger.error(\"Course ID not found on page. Make sure you are logged in and the slug is correct.\")\n"
    f"{indent}    return\n\n"
    f"{indent}@try_except_request\n"
    f"{indent}def download_course_by_id(self, course_id: int, path: Path, **kwargs):\n"
    f"{indent}    self.overwrite = kwargs.get(\"overwrite\")\n"
    f"{indent}    course = self.get_course(course_id)\n"
    f"{indent}    if not course:\n"
    f"{indent}        Logger.error(\"Course not found or inaccessible.\")\n"
    f"{indent}        return\n"
    f"{indent}    path = Path(path) if not isinstance(path, Path) else path\n"
    f"{indent}    defaults = {{\n"
    f"{indent}        \"slides\": True,\n"
    f"{indent}        \"datasets\": True,\n"
    f"{indent}        \"videos\": True,\n"
    f"{indent}        \"exercises\": True,\n"
    f"{indent}        \"subtitles\": [\"en\"],\n"
    f"{indent}        \"audios\": False,\n"
    f"{indent}        \"scripts\": True,\n"
    f"{indent}        \"last_attempt\": True,\n"
    f"{indent}        \"render_mp4\": False,\n"
    f"{indent}    }}\n"
    f"{indent}    for k, v in defaults.items():\n"
    f"{indent}        kwargs.setdefault(k, v)\n"
    f"{indent}    self.session.start()\n"
    f"{indent}    self.session.driver.minimize_window()\n"
    f"{indent}    Logger.info(f\"Start to download ({{course.id}}) {{course.title}}\")\n"
    f"{indent}    self.download_course(course, path, **kwargs)\n\n"
)
if 'def resolve_course_id' in text:
    pattern = r'(?s)^[ \t]*@try_except_request\n^[ \t]*def resolve_course_id[\s\S]*?(?=^[ \t]*def list_completed_tracks)'
    text = re.sub(pattern, method, text, flags=re.M)
else:
    text = text[:m.start()] + method + text[m.start():]
utils.write_text(text)

text = utils.read_text()
old_video_block = """            if exercise.is_video:
                video = self._get_video(exercise.data.get("projector_key"))
                if not video:
                    continue
                video_path = path / "videos" / f"ch{chapter.number}_{video_counter}"
                if videos and video.video_mp4_link:
                    download_file(
                        video.video_mp4_link,
                        video_path.with_suffix(".mp4"),
                        overwrite=self.overwrite,
                    )
                if audios and video.audio_link:
                    download_file(
                        video.audio_link,
                        path / "audios" / f"ch{chapter.number}_{video_counter}.mp3",
                        False,
                        overwrite=self.overwrite,
                    )
                if scripts and video.script_link:
                    download_file(
                        video.script_link,
                        path / "scripts" / (video_path.name + "_script.md"),
                        False,
                        overwrite=self.overwrite,
                    )
                if subtitles and video.subtitles:
                    for sub in subtitles:
                        subtitle = self._get_subtitle(sub, video)
                        if not subtitle:
                            continue
                        download_file(
                            subtitle.link,
                            video_path.parent / (video_path.name + f"_{sub}.vtt"),
                            False,
                            overwrite=self.overwrite,
                        )
                video_counter += 1
"""
new_video_block = """            if exercise.is_video:
                projector_key = exercise.data.get("projector_key")
                video = self._get_video(projector_key)
                if not video:
                    continue

                render_mp4 = bool(kwargs.get("render_mp4"))
                video_base = f"ch{chapter.number}_{video_counter}"
                video_path = path / "videos" / video_base

                audio_path = None
                tmp_audio_path = None
                if video.audio_link:
                    if audios:
                        audio_path = path / "audios" / f"{video_base}.mp3"
                        download_file(
                            video.audio_link,
                            audio_path,
                            False,
                            overwrite=self.overwrite,
                        )
                    elif render_mp4:
                        import tempfile

                        tmp = tempfile.NamedTemporaryFile(
                            prefix="datacamp_", suffix=".mp3", delete=False
                        )
                        tmp.close()
                        tmp_audio_path = Path(tmp.name)
                        audio_path = tmp_audio_path
                        download_file(
                            video.audio_link,
                            audio_path,
                            False,
                            overwrite=True,
                        )

                if videos and video.video_mp4_link:
                    download_file(
                        video.video_mp4_link,
                        video_path.with_suffix(".mp4"),
                        overwrite=self.overwrite,
                    )
                elif videos and render_mp4:
                    if not audio_path:
                        Logger.warning("No audio link found; cannot render mp4.")
                    else:
                        try:
                            from .projector_mp4 import render_projector_mp4

                            timings_json = None
                            if getattr(video, "slide_deck", None) and getattr(
                                video.slide_deck, "timings", None
                            ):
                                timings_json = video.slide_deck.timings
                            render_projector_mp4(
                                self.session.driver,
                                projector_key,
                                timings_json or "[]",
                                audio_path,
                                video_path.with_suffix(".mp4"),
                                overwrite=bool(self.overwrite),
                            )
                        except Exception as e:
                            Logger.warning(
                                f"Failed to render mp4 for {projector_key}: {e}"
                            )
                        finally:
                            if tmp_audio_path and tmp_audio_path.exists():
                                try:
                                    tmp_audio_path.unlink()
                                except Exception:
                                    pass

                if scripts and video.script_link:
                    download_file(
                        video.script_link,
                        path / "scripts" / (video_path.name + "_script.md"),
                        False,
                        overwrite=self.overwrite,
                    )
                if subtitles and video.subtitles:
                    for sub in subtitles:
                        subtitle = self._get_subtitle(sub, video)
                        if not subtitle:
                            continue
                        download_file(
                            subtitle.link,
                            video_path.parent / (video_path.name + f"_{sub}.vtt"),
                            False,
                            overwrite=self.overwrite,
                        )
                video_counter += 1
"""
if old_video_block not in text:
    raise SystemExit("download_others video block not found for patching")
utils.write_text(text.replace(old_video_block, new_video_block))

downloader = Path("src/datacamp_downloader/downloader.py")
text = downloader.read_text()

course_id_pattern = r"(?s)^@app\.command\(\)\ndef course_id\([\s\S]*?(?=^@app\.command\(\)|\Z)"
course_id_block = (
    "\n\n@app.command()\n"
    "def course_id(value: str = typer.Argument(..., help=\"Course URL, slug, or numeric ID.\")):\n"
    "    \"\"\"Resolve a DataCamp course ID from a URL or slug.\"\"\"\n"
    "    course_id = datacamp.resolve_course_id(value)\n"
    "    if course_id:\n"
    "        typer.echo(course_id)\n"
)
if re.search(course_id_pattern, text, flags=re.M):
    text = re.sub(course_id_pattern, course_id_block.lstrip("\n"), text, flags=re.M)
else:
    anchor = re.search(r"^@app\.command\(\)\ndef courses\(", text, flags=re.M)
    if not anchor:
        raise SystemExit("courses command not found for inserting course_id")
    text = text[: anchor.start()] + course_id_block + text[anchor.start() :]

download_id_pattern = r"(?s)^@app\.command\(\)\ndef download_id\([\s\S]*?(?=^@app\.command\(\)|\Z)"
download_id_block = (
    "\n\n@app.command()\n"
    "def download_id(\n"
    "    value: str = typer.Argument(..., help=\"Course URL, slug, or numeric ID.\"),\n"
    "    path: Path = typer.Option(\n"
    "        Path(os.getcwd() + \"/Datacamp\"),\n"
    "        \"--path\",\n"
    "        \"-p\",\n"
    "        help=\"Path to the download directory.\",\n"
    "        dir_okay=True,\n"
    "        file_okay=False,\n"
    "    ),\n"
    "    only_videos: Optional[bool] = typer.Option(\n"
    "        False,\n"
    "        \"--only-videos\",\n"
    "        is_flag=True,\n"
    "        help=\"Shortcut for --no-slides --no-datasets --no-exercises --no-scripts --videos --render-mp4.\",\n"
    "    ),\n"
    "    render_mp4: Optional[bool] = typer.Option(\n"
    "        False,\n"
    "        \"--render-mp4/--no-render-mp4\",\n"
    "        help=\"Render projector videos to mp4 when no direct mp4 link exists (requires ffmpeg).\",\n"
    "    ),\n"
    "    slides: Optional[bool] = typer.Option(True, \"--slides/--no-slides\", help=\"Download slides.\"),\n"
    "    datasets: Optional[bool] = typer.Option(True, \"--datasets/--no-datasets\", help=\"Download datasets.\"),\n"
    "    videos: Optional[bool] = typer.Option(True, \"--videos/--no-videos\", help=\"Download videos.\"),\n"
    "    exercises: Optional[bool] = typer.Option(True, \"--exercises/--no-exercises\", help=\"Download exercises.\"),\n"
    "    subtitles: Optional[List[Language]] = typer.Option(\n"
    "        [Language.EN.value],\n"
    "        \"--subtitles\",\n"
    "        \"-st\",\n"
    "        help=\"Choose subtitles to download.\",\n"
    "        case_sensitive=False,\n"
    "    ),\n"
    "    audios: Optional[bool] = typer.Option(False, \"--audios/--no-audios\", help=\"Download audio files.\"),\n"
    "    scripts: Optional[bool] = typer.Option(\n"
    "        True,\n"
    "        \"--scripts/--no-scripts\",\n"
    "        \"--transcript/--no-transcript\",\n"
    "        show_default=True,\n"
    "        help=\"Download scripts or transcripts.\",\n"
    "    ),\n"
    "    python_file: Optional[bool] = typer.Option(\n"
    "        True,\n"
    "        \"--python-file/--no-python-file\",\n"
    "        show_default=True,\n"
    "        help=\"Download your own solution as a python file if available.\",\n"
    "    ),\n"
    "    warnings: Optional[bool] = typer.Option(\n"
    "        True,\n"
    "        \"--no-warnings\",\n"
    "        flag_value=False,\n"
    "        is_flag=True,\n"
    "        help=\"Disable warnings.\",\n"
    "    ),\n"
    "    overwrite: Optional[bool] = typer.Option(\n"
    "        False,\n"
    "        \"--overwrite\",\n"
    "        \"-w\",\n"
    "        flag_value=True,\n"
    "        is_flag=True,\n"
    "        help=\"Overwrite files if exist.\",\n"
    "    ),\n"
    "):\n"
    "    \"\"\"Download a course by URL, slug, or numeric ID (even if not completed).\"\"\"\n"
    "    if only_videos:\n"
    "        slides = False\n"
    "        datasets = False\n"
    "        exercises = False\n"
    "        scripts = False\n"
    "        audios = False\n"
    "        videos = True\n"
    "        subtitles = [Language.NONE.value]\n"
    "        render_mp4 = True\n"
    "    Logger.show_warnings = warnings\n"
    "    course_id = datacamp.resolve_course_id(value)\n"
    "    if not course_id:\n"
    "        return\n"
    "    datacamp.download_course_by_id(\n"
    "        course_id,\n"
    "        path,\n"
    "        slides=slides,\n"
    "        datasets=datasets,\n"
    "        videos=videos,\n"
    "        exercises=exercises,\n"
    "        subtitles=subtitles,\n"
    "        audios=audios,\n"
    "        scripts=scripts,\n"
    "        render_mp4=render_mp4,\n"
    "        overwrite=overwrite,\n"
    "        last_attempt=python_file,\n"
    "    )\n"
)
if re.search(download_id_pattern, text, flags=re.M):
    text = re.sub(download_id_pattern, download_id_block.lstrip("\n"), text, flags=re.M)
else:
    anchor = re.search(r"^@app\.command\(\)\ndef reset\(", text, flags=re.M)
    if not anchor:
        text = text + download_id_block
    else:
        text = text[: anchor.start()] + download_id_block + text[anchor.start() :]

downloader.write_text(text)

import compileall
ok = compileall.compile_dir("src/datacamp_downloader", quiet=1)
if not ok:
    raise SystemExit("python syntax check failed after patching")
PY
        '';
        propagatedBuildInputs = with pkgs.python3Packages; [
          beautifulsoup4
          requests
          selenium
          undetected-chromedriver
          texttable
          termcolor
          colorama
          typer
        ] ++ [ tomd webdriver-manager ];
        doCheck = false;
      };
    in
    {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = [
        # Existing
        pkgs.vim
        pkgs.direnv
        pkgs.sshs
        pkgs.glow
        pkgs.nushell
        pkgs.carapace

        # Core tools
        pkgs.tmux
        pkgs.fzf
        pkgs.fd
        pkgs.ripgrep
        pkgs.bat
        pkgs.zoxide
        pkgs.atuin
        pkgs.eza
        pkgs.yazi
        pkgs.tree
        pkgs.go
        pkgs.nodejs
        pkgs.bun
        pkgs.pnpm
        pkgs.ruby
        pkgs.rustup
        pkgs.xh
        pkgs.kubectx
        pkgs.starship
        pkgs.jq
        pkgs.yq

        # Knowledge graph
        pkgs.oxigraph

        # Security tools
        pkgs.nmap
        pkgs.gobuster
        pkgs.ffuf
        pkgs.ngrok

        # Developer utilities
        pkgs.coreutils                       # GNU coreutils (timeout, etc.)
        ocx
        amp                                  # Amp CLI from ampcode.com
        pkgs.playwright-driver
        pkgs.pv
        pkgs.watch
        pkgs.stow
        pkgs.aichat
        pkgs.gemini-cli
        pkgs.lazygit
        pkgs.uv
        pkgs.delta
        pkgs.cloc
        pkgs.cmatrix
        pkgs.mactop
        pkgs.yt-dlp
        pkgs.ffmpeg
        pkgs.python3
        pkgs.python3Packages.pymupdf
        datacamp-downloader

        # PDF and Document Tools
        pkgs.pandoc
        pkgs.tesseract
        pkgs.pdfgrep
        pkgs.qpdf
        pkgs.gpgme
        pkgs.python3Packages.weasyprint     # HTML to PDF (replaces wkhtmltopdf)
        pkgs.python3Packages.pdfplumber
        pkgs.python3Packages.tabulate
        pkgs.python3Packages.pdfkit

        # Fonts
        pkgs.nerd-fonts.jetbrains-mono

        # Cloud CLIs
        pkgs.kubectl
        pkgs.awscli2
        pkgs.google-cloud-sdk
        pkgs.doctl
        pkgs.flyctl
        pkgs.terraform
        pkgs.gh
        pkgs.wrangler
        pkgs.supabase-cli

        # Database tools
        pkgs.sqlite
        pkgs.sqlite-utils
      ];
      nix.enable = false;  # Let Determinate Systems manage Nix
      programs.zsh.enable = true;  # default shell on catalina
      system.configurationRevision = self.rev or self.dirtyRev or null;
      system.stateVersion = 4;
      nixpkgs.hostPlatform = "aarch64-darwin";
      nixpkgs.config.allowUnfree = true;
      security.pam.services.sudo_local.touchIdAuth = true;
      security.pam.services.sudo_local.watchIdAuth = true;   # Apple Watch for sudo (Mac mini has no Touch ID)
      security.pam.services.sudo_local.reattach = true;      # Fix auth inside tmux/screen

      system.primaryUser = "klaudioz";
      users.users.klaudioz.home = "/Users/klaudioz";
      home-manager.backupFileExtension = "backup";

      system.defaults = {
        dock.autohide = true;
        dock.orientation = "left";
        dock.mru-spaces = false;
        dock.persistent-apps = [];  # Empty dock - no pinned apps
        dock.expose-group-apps = true;  # Group windows by app in Mission Control
        finder.AppleShowAllExtensions = true;
        finder.FXPreferredViewStyle = "clmv";
        finder.CreateDesktop = false;           # Hide all desktop icons
        finder.NewWindowTarget = "Other";        # Custom location for new windows
        finder.NewWindowTargetPath = "file:///Users/klaudioz/Downloads/";  # Open Downloads by default
        loginwindow.LoginwindowText = "m4-mini";
        screencapture.location = "~/Pictures/screenshots";
        screencapture.target = "clipboard";     # Cmd+Shift+4 copies to clipboard
        screensaver.askForPasswordDelay = 10;
        # Keyboard: fast but controllable key repeat
        NSGlobalDomain.KeyRepeat = 2;           # Fast (default: 6)
        NSGlobalDomain.InitialKeyRepeat = 15;   # Short delay (default: 25)
        # Menu bar hiding is set via activation script (value 2 = auto-hide with notifications)
      };

      # Kernel / launchd resource limits (avoid apps failing with "error.SystemResources").
      launchd.daemons.sysctl-maxproc = {
        serviceConfig = {
          ProgramArguments = [
            "/usr/sbin/sysctl"
            "-w"
            "kern.maxproc=10000"
            "kern.maxprocperuid=10000"
          ];
          RunAtLoad = true;
          StandardOutPath = "/tmp/sysctl-maxproc.out";
          StandardErrorPath = "/tmp/sysctl-maxproc.err";
        };
      };

      launchd.daemons.launchctl-maxproc = {
        serviceConfig = {
          ProgramArguments = [
            "/bin/launchctl"
            "limit"
            "maxproc"
            "10000"
            "10000"
          ];
          RunAtLoad = true;
          StandardOutPath = "/tmp/launchctl-maxproc.out";
          StandardErrorPath = "/tmp/launchctl-maxproc.err";
        };
      };

      launchd.daemons.launchctl-maxfiles = {
        serviceConfig = {
          ProgramArguments = [
            "/bin/launchctl"
            "limit"
            "maxfiles"
            "524288"
            "524288"
          ];
          RunAtLoad = true;
          StandardOutPath = "/tmp/launchctl-maxfiles.out";
          StandardErrorPath = "/tmp/launchctl-maxfiles.err";
        };
      };

      launchd.daemons.blocky = {
        serviceConfig = {
          Label = "com.klaudioz.blocky";
          ProgramArguments = [
            "/opt/homebrew/sbin/blocky"
            "--config"
            "/Users/klaudioz/.config/blocky/config.yml"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "/tmp/blocky.out";
          StandardErrorPath = "/tmp/blocky.err";
        };
      };

      # Set desktop wallpaper and other settings that need non-boolean values
      system.activationScripts.postActivation.text = ''
        # Auto-hide menu bar (2) - keeps notifications working unlike full hide (1)
        sudo -u klaudioz defaults write NSGlobalDomain _HIHideMenuBar -int 2

        osascript -e 'tell application "System Events" to tell every desktop to set picture to POSIX file "/Users/klaudioz/dotfiles/wallpaper.jpeg"'

        # Deploy Chrome managed policies (force-install extensions)
        mkdir -p "/Library/Managed Preferences"
        cp /Users/klaudioz/dotfiles/chrome/com.google.Chrome.plist "/Library/Managed Preferences/"
        chown root:wheel "/Library/Managed Preferences/com.google.Chrome.plist"
        chmod 644 "/Library/Managed Preferences/com.google.Chrome.plist"

        # Install gh-dash extension (runs as user, idempotent)
        sudo -u klaudioz ${pkgs.gh}/bin/gh extension install dlvhdr/gh-dash 2>/dev/null || true

        # Install takopi via uv (Telegram bridge for agent CLIs)
        sudo -u klaudioz ${pkgs.uv}/bin/uv tool install -U takopi --no-cache --with-editable /Users/klaudioz/dotfiles/takopi-plugins/takopi-dotfiles 2>/dev/null || true

        # Install sqlite-tui via uv (SQLite database TUI)
        sudo -u klaudioz ${pkgs.uv}/bin/uv tool install -U sqlite-tui 2>/dev/null || true

        # Power management for Bluetooth wake reliability (Mac mini M4)
        # Prevents deep sleep that breaks Bluetooth connections
        /usr/bin/pmset -a standby 0           # Disable deep sleep (hibernation)
        /usr/bin/pmset -a proximitywake 0     # Disable wake from nearby iCloud devices
        /usr/bin/pmset -a ttyskeepawake 1     # Prevent sleep during SSH/remote sessions
        /usr/bin/pmset -a tcpkeepalive 1      # Maintain network connections during sleep
        /usr/bin/pmset -a womp 1              # Enable Wake-on-LAN
        /usr/bin/pmset -a powernap 0          # Disable Power Nap (can interfere with BT)
        /usr/bin/pmset -a sleep 0             # Never auto-sleep (manual sleep only)
        /usr/bin/pmset -a displaysleep 0      # Display never turns off

        # Enable Bluetooth devices to wake computer
        /usr/bin/defaults -currentHost write .Bluetooth RemoteWakeEnabled -bool true

        # Symlink colima config from dotfiles
        sudo -u klaudioz mkdir -p /Users/klaudioz/.colima/default
        sudo -u klaudioz ln -sf /Users/klaudioz/dotfiles/colima/default/colima.yaml /Users/klaudioz/.colima/default/colima.yaml

        # Configure DNS to use blocky for ad-blocking
        /usr/sbin/networksetup -setdnsservers Wi-Fi 127.0.0.1
        /usr/sbin/networksetup -setdnsservers Ethernet 127.0.0.1 2>/dev/null || true
      '';

      # Homebrew needs to be installed on its own!
      homebrew.enable = true;
      homebrew.global.lockfiles = true;  # --no-lock was removed from brew bundle

      homebrew.taps = [
        "FelixKratz/formulae"
        "joncrangle/tap"
        "nikitabobko/tap"
        "productdevbook/tap"
        "shopify/shopify"
        "steipete/tap"
        "tw93/tap"
        "unhappychoice/tap"
        {
          name = "chmouel/lazyworktree";
          clone_target = "https://github.com/chmouel/lazyworktree";
        }
        {
          name = "lbjlaq/antigravity-manager";
          clone_target = "https://github.com/lbjlaq/Antigravity-Manager";
        }
      ];

      homebrew.casks = [
        "wireshark-app"
        "amazon-workspaces"
        "google-chrome"
        "google-chrome@beta"
        "ghostty"
        "nikitabobko/tap/aerospace"
        "hammerspoon"
        "telegram"
        "tailscale"
        "slack"
        "discord"
        "droid"
        "obsidian"
        "arc"
        "cursor"
        "windsurf"
        "qspace-pro"
        "granola"
        "firefox"
        "vial"
        "raycast"
        "gitify"
        "1password"
        "linear-linear"
        "bettermouse"
        "itsycal"
        "qbittorrent"
        "visual-studio-code"
        "zed"
        "zoom"
        "sf-symbols"
        "font-sketchybar-app-font"
        "xbar"
        "codex"
        "codex-app"
        "steipete/tap/repobar"
        "steipete/tap/trimmy"
        "setapp"
        "productdevbook/tap/portkiller"
        "powershell"
        "warp"
        "karabiner-elements"
        "chmouel/lazyworktree/lazyworktree"
        "claude"
        "libreoffice"
        "lbjlaq/antigravity-manager/antigravity-tools"
      ];

      homebrew.brews = [
        "gitingest"
        "neovim"
        "cmake"
        "imagemagick"
        "ical-buddy"
        "ifstat"
        "overmind"
        "opencode"
        "blueutil"
        "libpq"
        "postgresql@18"
        "pgvector"
        "render"
        "cliproxyapi"
        "tw93/tap/mole"
        "felixkratz/formulae/sketchybar"
        "felixkratz/formulae/borders"
        "joncrangle/tap/sketchybar-system-stats"
        "tailspin"
        "snitch"
        "unhappychoice/tap/gitlogue"
        "blocky"
        "shopify-cli"
        "docker"
        "docker-compose"
        "colima"
        "qpdf"
        "steipete/tap/wacli"
        "vercel-cli"
      ];
    };
  in
  {
    darwinConfigurations."Claudios-MacBook-Pro" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        configuration
        home-manager.darwinModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.klaudioz = import ./home.nix;
        }
      ];
    };

    darwinConfigurations."m4-mini" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        configuration
        home-manager.darwinModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.klaudioz = import ./home.nix;
        }
      ];
    };

    # Expose the package set, including overlays, for convenience.
    darwinPackages = self.darwinConfigurations."Claudios-MacBook-Pro".pkgs;
  };
}
