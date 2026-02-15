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
if "def resolve_course_id" not in text:
    m = re.search(r"^([ \\t]*)def list_completed_tracks", text, re.M)
    if not m:
        raise SystemExit("list_completed_tracks block not found for patching")
    indent = m.group(1)
    method = (
        f"\n{indent}@try_except_request\n"
        f"{indent}def resolve_course_id(self, value: str):\n"
        f"{indent}    if value.isnumeric():\n"
        f"{indent}        return int(value)\n\n"
        f"{indent}    if value.startswith(\"http\"):\n"
        f"{indent}        url = value\n"
        f"{indent}    else:\n"
        f"{indent}        url = f\"https://app.datacamp.com/learn/courses/{{value}}\"\n\n"
        f"{indent}    html = self.session.get(url)\n"
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
        f"{indent}    Logger.error(\"Course ID not found on page. Make sure you are logged in and the slug is correct.\")\n"
        f"{indent}    return\n\n"
    )
    text = text[:m.start()] + method + text[m.start():]
    utils.write_text(text)

downloader = Path("src/datacamp_downloader/downloader.py")
text = downloader.read_text()
if "def course_id(" not in text:
    needle = "def courses("
    idx = text.find(needle)
    if idx == -1:
        raise SystemExit("courses command not found for patching")
    insert_after = text.find("\\n\\n", idx)
    if insert_after == -1:
        insert_after = idx
    command = (
        "\n\n@app.command()\n"
        "def course_id(value: str = typer.Argument(..., help=\"Course URL, slug, or numeric ID.\")):\n"
        "    \"\"\"Resolve a DataCamp course ID from a URL or slug.\"\"\"\n"
        "    course_id = datacamp.resolve_course_id(value)\n"
        "    if course_id:\n"
        "        typer.echo(course_id)\n"
    )
    text = text[:insert_after] + command + text[insert_after:]
    downloader.write_text(text)
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
        "wireshark"
        "amazon-workspaces"
        "google-chrome"
        "google-chrome@beta"
        "ghostty"
        "nikitabobko/tap/aerospace"
        "hammerspoon"
        "telegram"
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
