#!/usr/bin/env bash
# =============================================================================
# script.sh - Full Arch Linux setup from Brodie Robertson's repos
#
#   Uses the four repo zips (put them next to this script or in ~/Downloads):
#     dotfiles-master*.zip   scripts-master*.zip   st-master*.zip   dmenu-master*.zip
#   Anything missing is fetched from the Internet Archive / GitHub instead.
#
#   What it does
#     1. installs packages his configs and scripts actually use (repo + AUR via yay)
#     2. builds and installs HIS st and dmenu builds (his patches are already applied)
#     3. installs his scripts to ~/scripts (the path his shell config expects)
#     4. applies his dotfiles: zsh/bash, X11, WM, sxhkd, polybar, nvim (+ plugins),
#        dunst, ranger, lf, mpv, rofi, GTK/Qt themes, fonts, app configs ...
#     5. fixes the parts tied to his own machine (/home/brodie paths, broken
#        symlinks, his monitor names, cache/junk files)
#     6. installs powerline-shell with HIS purple theme and makes it the prompt
#        in zsh (set as your login shell) and bash
#
# Usage:
#   chmod +x script.sh
#   ./script.sh                      # awesome WM (what his .xinitrc launches)
#   ./script.sh --wm bspwm           # or: awesome | bspwm | i3 | hyprland
#   ./script.sh --zips ~/somewhere   # folder holding the zips
#   ./script.sh -y                   # no confirmation prompts
#   ./script.sh --no-heavy-apps      # skip GIMP/OBS/Kdenlive/Blender/VSCodium/Brave/Thunderbird
#   ./script.sh --no-packages        # only apply configs (no pacman/yay)
#
# Run as your normal user, NOT root. Existing files are backed up first.
# =============================================================================
set -euo pipefail

# ---------- options -----------------------------------------------------------
WM="awesome"; ZIPDIR=""; ASSUME_YES=0; SKIP_PKGS=0; HEAVY=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wm)            WM="${2,,}"; shift 2 ;;
    --zips)          ZIPDIR="$2"; shift 2 ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    --no-packages)   SKIP_PKGS=1; shift ;;
    --no-heavy-apps) HEAVY=0; shift ;;
    -h|--help)       sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done
case "$WM" in
  awesome)  WMBIN=awesome ;;
  bspwm)    WMBIN=bspwm ;;
  i3)       WMBIN=i3 ;;
  hyprland) WMBIN=Hyprland ;;
  *) echo "--wm must be awesome, bspwm, i3 or hyprland" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${HOME}/.cache/brodie-setup"
BACKUP="${HOME}/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
SNAPSHOT_TS="20201231045615"

log()  { printf '\e[1;35m[+]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[!]\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m[x]\e[0m %s\n' "$*" >&2; exit 1; }
confirm() { [[ $ASSUME_YES -eq 1 ]] && return 0; read -rp "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy] ]]; }

[[ $EUID -ne 0 ]] || die "Run as your normal user, not root."
if [[ $SKIP_PKGS -eq 0 ]]; then
  command -v pacman >/dev/null || die "This script is for Arch-based systems (pacman not found)."
  command -v sudo   >/dev/null || die "sudo is required."
fi

# ---------- package lists (taken from his configs, scripts and README deps) --
PKG_CORE=(base-devel git curl wget unzip rsync python python-pipx lua ruby jq bc
  zsh zsh-syntax-highlighting zsh-you-should-use pkgfile
  xorg-server xorg-xinit xorg-xsetroot xorg-xset xorg-xrdb xorg-xrandr xorg-xprop
  xorg-xwininfo xorg-xev xorg-xinput xorg-xmodmap xclip xdotool
  libx11 libxft libxinerama fontconfig freetype2)
PKG_DESKTOP=(picom dunst libnotify rofi hsetroot networkmanager network-manager-applet
  udiskie flameshot betterlockscreen pipewire pipewire-pulse pipewire-alsa wireplumber
  pavucontrol alsa-utils playerctl xdg-utils xdg-user-dirs qt5ct lxappearance imwheel)
PKG_CLI=(neovim nodejs npm fzf ripgrep ranger lf vifm joshuto btop neofetch fastfetch
  broot calcurse newsboat tmux highlight mediainfo glow pandoc-cli poppler sysstat
  acpi speedtest-cli unrar perl php v4l-utils prettyping dragon-drop simple-mtpfs
  tabbed lemonbar-xft-git pistol-git)
PKG_MEDIA=(mpv mpd ncmpcpp mpdris2 zathura zathura-pdf-mupdf nsxiv transmission-cli tremc)
PKG_FONTS=(ttf-jetbrains-mono ttf-hack-nerd otf-ipafont ttf-symbola ttf-roboto
  noto-fonts noto-fonts-emoji ttf-font-awesome powerline-fonts)
PKG_GUI=(firefox kitty alacritty pcmanfm)
PKG_HEAVY=(gimp obs-studio kdenlive blender vscodium-bin brave-bin thunderbird)
case "$WM" in
  awesome)  PKG_WM=(awesome sxhkd) ;;
  bspwm)    PKG_WM=(bspwm sxhkd polybar xdo tdrop) ;;
  i3)       PKG_WM=(i3-wm i3blocks i3lock sxhkd) ;;
  hyprland) PKG_WM=(hyprland waybar tofi xdg-desktop-portal-hyprland grim slurp wl-clipboard) ;;
esac

FAILED_PKGS=(); MISSING_PKGS=()
install_pkgs() {     # sorts names into repo / AUR / not-found, then installs
  local repo=() aur=() p
  for p in "$@"; do
    if pacman -Si "$p" >/dev/null 2>&1; then repo+=("$p")
    elif yay -Si "$p" >/dev/null 2>&1;  then aur+=("$p")
    else MISSING_PKGS+=("$p"); fi
  done
  if [[ ${#repo[@]} -gt 0 ]] && ! sudo pacman -S --needed --noconfirm "${repo[@]}"; then
    for p in "${repo[@]}"; do sudo pacman -S --needed --noconfirm "$p" || FAILED_PKGS+=("$p"); done
  fi
  if [[ ${#aur[@]} -gt 0 ]] && ! yay -S --needed --noconfirm "${aur[@]}"; then
    for p in "${aur[@]}"; do yay -S --needed --noconfirm "$p" || FAILED_PKGS+=("$p"); done
  fi
}

# ---------- 1. packages -------------------------------------------------------
if [[ $SKIP_PKGS -eq 0 ]]; then
  log "Updating system and installing build tools..."
  sudo pacman -Syu --needed --noconfirm base-devel git curl unzip

  if ! command -v yay >/dev/null; then
    log "Bootstrapping yay (AUR helper)..."
    tmp=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
  fi

  log "Installing his software stack for WM: ${WM}"
  install_pkgs "${PKG_CORE[@]}" "${PKG_WM[@]}" "${PKG_DESKTOP[@]}" "${PKG_CLI[@]}" \
               "${PKG_MEDIA[@]}" "${PKG_FONTS[@]}" "${PKG_GUI[@]}"
  if [[ $HEAVY -eq 1 ]] && confirm "Also install the big apps he has configs for (GIMP, OBS, Kdenlive, Blender, VSCodium, Brave, Thunderbird)?"; then
    install_pkgs "${PKG_HEAVY[@]}"
  fi
  sudo systemctl enable --now NetworkManager.service 2>/dev/null || true
  sudo pkgfile --update >/dev/null 2>&1 || true
fi

# ---------- 2. get the four repos --------------------------------------------
log "Locating the repo zips..."
rm -rf "$WORK"; mkdir -p "$WORK"

find_zip() {
  local pat="$1" d f
  for d in "$ZIPDIR" "$SCRIPT_DIR" "$PWD" "$HOME/Downloads" "$HOME"; do
    [[ -n "$d" && -d "$d" ]] || continue
    f=$(ls -t "$d"/$pat 2>/dev/null | head -n1 || true)
    [[ -n "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}

unpack_zip() {       # unpack_zip <zip> <name>  ->  $WORK/<name>
  local tmp="$WORK/tmp_$2" top
  rm -rf "$tmp"; mkdir -p "$tmp"
  unzip -q "$1" -d "$tmp" || return 1
  top=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)
  [[ -n "$top" ]] || return 1
  mv "$top" "$WORK/$2"; rm -rf "$tmp"
}

get_repo() {         # get_repo <name> <zip-glob> <github repo>
  local name="$1" pat="$2" gh="$3" zip url
  if zip=$(find_zip "$pat"); then
    log "Using $zip"; unpack_zip "$zip" "$name" && return 0
  fi
  for url in "https://web.archive.org/web/${SNAPSHOT_TS}id_/https://github.com/${gh}/archive/master.zip" \
             "https://github.com/${gh}/archive/refs/heads/master.zip"; do
    if curl -fsSL --retry 3 -o "$WORK/$name.zip" "$url" 2>/dev/null && unzip -tq "$WORK/$name.zip" >/dev/null 2>&1; then
      log "Downloaded ${gh} from ${url%%/https*}"; unpack_zip "$WORK/$name.zip" "$name" && return 0
    fi
  done
  git clone --depth 1 "https://github.com/${gh}.git" "$WORK/$name" && rm -rf "$WORK/$name/.git" && return 0
  return 1
}

get_repo dotfiles "dotfiles-master*.zip" BrodieRobertson/dotfiles || die "Could not get the dotfiles."
get_repo scripts  "scripts-master*.zip"  BrodieRobertson/scripts  || warn "Could not get his scripts; skipping them."
get_repo st       "st-master*.zip"       BrodieRobertson/st       || warn "Could not get his st; skipping it."
get_repo dmenu    "dmenu-master*.zip"    BrodieRobertson/dmenu    || warn "Could not get his dmenu; skipping it."

DOT="$WORK/dotfiles"; SCR="$WORK/scripts"

# ---------- 3. clean up machine-specific bits --------------------------------
log "Fixing paths and links that only worked on his machine..."

# Symlinks pointing into /home/brodie/repos/dotfiles -> real copies; other dead links removed
for tree in "$DOT" "$SCR"; do
  [[ -d "$tree" ]] || continue
  while IFS= read -r -d '' l; do
    t=$(readlink "$l")
    if [[ "$t" == /home/brodie/repos/dotfiles/* ]]; then
      rel="${t#/home/brodie/repos/dotfiles/}"
      rm -f "$l"
      [[ -f "$DOT/$rel" ]] && cp -a "$DOT/$rel" "$l"
    elif [[ "$t" == /* ]]; then
      rm -f "$l"; warn "Dropped link to his private repo: ${l#"$WORK"/}"
    fi
  done < <(find "$tree" -type l -print0)
done

# Junk / caches / his personal state
rm -rf "$DOT/config/mpv/watch_later" "$DOT/config/transmission-daemon/"settings.json.tmp.* \
       "$DOT/.calcurse/.calcurse.pid" "$DOT/config/vifm/vifminfo" "$DOT/config/vifm/vifminfo.json" \
       "$DOT/config/nvim/.netrwhist" "$DOT/config/bashtop/error.log" "$DOT/.zcompdump" \
       "$DOT/config/flameshot/flameshot.inio" "$DOT/config/blender/"*/config/recent-files.txt 2>/dev/null || true

# /home/brodie -> your home, in every text file
for tree in "$DOT" "$SCR"; do
  [[ -d "$tree" ]] || continue
  grep -rIl --null '/home/brodie' "$tree" 2>/dev/null | xargs -0 -r sed -i "s#/home/brodie#${HOME}#g"
done

# His aliases use doas; switch to sudo if you don't have doas
if ! command -v doas >/dev/null && [[ -d "$DOT/config/shellconfig" ]]; then
  sed -i 's/\bdoas\b/sudo/g' "$DOT/config/shellconfig/"* 2>/dev/null || true
fi

# Fill the nvim plugin folders (they are git submodules, so the zip has them empty)
if [[ -f "$DOT/.gitmodules" ]]; then
  log "Fetching his Neovim plugins..."
  while read -r key path; do
    name="${key%.path}"
    url=$(git config -f "$DOT/.gitmodules" --get "${name}.url" || true)
    dir="$DOT/$path"
    if [[ -n "$url" ]] && { [[ ! -d "$dir" ]] || [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; }; then
      rm -rf "$dir"; git clone -q --depth 1 "$url" "$dir" || warn "Plugin failed: $url"
    fi
  done < <(git config -f "$DOT/.gitmodules" --get-regexp '^submodule\..*\.path$' || true)
fi

# ---------- 4. WM / session wiring -------------------------------------------
log "Setting up the ${WM} session..."

# xinitrc: his autostart list, ending with the chosen WM
if [[ -f "$DOT/.xinitrc" ]]; then
  sed -i "s/^exec .*/exec ${WMBIN}/" "$DOT/.xinitrc"
  grep -q '^exec ' "$DOT/.xinitrc" || echo "exec ${WMBIN}" >> "$DOT/.xinitrc"
  sed -i 's#xrdb -load ~/.config/X11/xresources#xrdb -load ~/.Xresources#' "$DOT/.xinitrc"
fi

# Login: tty1 auto-starts the chosen session
if [[ "$WM" == hyprland ]]; then
  START_CMD="pgrep Hyprland || Hyprland"
else
  START_CMD="pgrep -x ${WMBIN} >/dev/null || startx \"\$XDG_CONFIG_HOME/X11/xinitrc\""
fi
[[ -f "$DOT/.zprofile" ]] && sed -i "s#pgrep Hyprland || Hyprland#${START_CMD//&/\\&}#" "$DOT/.zprofile"
if [[ -f "$DOT/.profile" ]]; then
  sed -i "s#pgrep bspwm || startx .*#${START_CMD//&/\\&}#" "$DOT/.profile"
  sed -i 's#\. ~/\.config/bashrc#. ~/.bashrc#' "$DOT/.profile"
fi

# Environment defaults ($WM, terminal, launcher) to match the session
if [[ -f "$DOT/.zshenv" ]]; then
  sed -i "s/^export WM=.*/export WM=\"${WMBIN}\"/" "$DOT/.zshenv"
  if [[ "$WM" != hyprland ]]; then
    sed -i -e 's/^export TERMINAL=.*/export TERMINAL="st"/' \
           -e 's/^export LAUNCHER=.*/export LAUNCHER="dmenu_run"/' \
           -e 's/^export BROWSER=.*/export BROWSER="firefox"/' \
           -e 's/^export PAGER="moar"/export PAGER="less"/' "$DOT/.zshenv"
  fi
fi

# bspwm: his monitor names -> whatever monitors you have; re-enable his bspwm keybinds
if [[ "$WM" == bspwm ]]; then
  if [[ -f "$DOT/config/bspwm/bspwmrc" ]]; then
    sed -i '/^bspc monitor /d' "$DOT/config/bspwm/bspwmrc"
    sed -i '/###---MONITORS---###/a for m in $(bspc query -M --names); do bspc monitor "$m" -d 1 2 3 4 5 6 7 8 9 10; break; done' \
      "$DOT/config/bspwm/bspwmrc"
    chmod +x "$DOT/config/bspwm/bspwmrc"
  fi
  if [[ -f "$DOT/config/sxhkd/sxhkdrc" ]]; then
    sed -i '2,/^#---System Control---#/{/^#---System Control---#/!{s/^# //;s/^#$//;s/^ \([a-zA-Z]\)/\1/}}' "$DOT/config/sxhkd/sxhkdrc"
  fi
  if [[ -f "$SCR/polybar/launchpolybar" ]]; then
    sed -i 's#^polybar bar &#for m in $(polybar --list-monitors | cut -d: -f1); do MONITOR=$m polybar bar \& done#' \
      "$SCR/polybar/launchpolybar"
  fi
fi

# ---------- 5. shell + purple powerline prompt -------------------------------
# bash: turn ON his own commented-out powerline block, turn OFF starship
if [[ -f "$DOT/.bashrc" ]]; then
  sed -i '/---Powerline Prompt---/,/^# -----/{/^# -/!s/^#//}' "$DOT/.bashrc"
  sed -i 's/^eval "\$(starship init bash)"/# &/' "$DOT/.bashrc"
  sed -i -E 's#^source ([^ ]+)$#[ -f \1 ] \&\& source \1#' "$DOT/.bashrc"
fi
# zsh: swap spaceship for powerline-shell
if [[ -f "$DOT/.zshrc" ]]; then
  sed -i 's#^source /usr/lib/spaceship-prompt/spaceship.zsh#\# &#' "$DOT/.zshrc"
  sed -i 's#^eval "$(lua ~/.local/bin/z.lua#[ -f ~/.local/bin/z.lua ] \&\& eval "$(lua ~/.local/bin/z.lua#' "$DOT/.zshrc"
  cat >> "$DOT/.zshrc" <<'EOF'

# ---Powerline Prompt (purple)---
function powerline_precmd() { PS1="$(powerline-shell --shell zsh $?)"; }
function install_powerline_precmd() {
  for s in "${precmd_functions[@]}"; do [ "$s" = "powerline_precmd" ] && return; done
  precmd_functions+=(powerline_precmd)
}
[ "$TERM" != "linux" ] && install_powerline_precmd
EOF
fi
# his theme.py points at "~/..."; give it an absolute path
[[ -f "$DOT/config/powerline-shell/config.json" ]] && \
  sed -i "s#\"~/.config/powerline-shell/theme.py\"#\"${HOME}/.config/powerline-shell/theme.py\"#" "$DOT/config/powerline-shell/config.json"

# ---------- 6. apply everything ----------------------------------------------
log "Applying his dotfiles (backups -> ${BACKUP})..."
mkdir -p "$BACKUP"
put() {              # put <src> <dest>: back up dest if present, then copy src there
  local s="$1" d="$2"
  [[ -e "$s" || -L "$s" ]] || return 0
  if [[ -e "$d" || -L "$d" ]]; then
    mkdir -p "$BACKUP/$(dirname "${d#"$HOME"/}")"
    mv "$d" "$BACKUP/${d#"$HOME"/}"
  fi
  mkdir -p "$(dirname "$d")"
  cp -a "$s" "$d"
}

# home dotfiles
for f in .bash_profile .bashrc .profile .Xresources .xinitrc .Xmodmap .imwheelrc .zprofile .zshenv .zshrc .calcurse; do
  put "$DOT/$f" "$HOME/$f"
done
# zsh reads from ZDOTDIR=~/.config/zsh (set in his .zshenv)
put "$DOT/.zshrc"    "$HOME/.config/zsh/.zshrc"
put "$DOT/.zprofile" "$HOME/.config/zsh/.zprofile"
mkdir -p "$HOME/.cache/zsh" "$HOME/.local/share/zsh" "$HOME/.local/share/bash"
# X11 folder (xinitrc / xresources / xmodmap) used by startx and his profile
put "$DOT/.xinitrc"     "$HOME/.config/X11/xinitrc"
put "$DOT/.Xresources"  "$HOME/.config/X11/xresources"
put "$DOT/.Xmodmap"     "$HOME/.config/X11/xmodmap"

# ~/.config: every folder/file, with the special locations his installer used
for item in "$DOT"/config/*; do
  name=$(basename "$item")
  case "$name" in
    X11|zsh) ;;                                        # handled above
    GIMP)
      put "$item/filters"  "$HOME/.config/GIMP/2.10/filters"
      put "$item/patterns" "$HOME/.config/GIMP/2.10/patterns" ;;
    VSCodium)
      put "$item/keybindings.json" "$HOME/.config/VSCodium/User/keybindings.json"
      put "$item/settings.json"    "$HOME/.config/VSCodium/User/settings.json" ;;
    joplin)
      put "$item/keymap.json" "$HOME/.config/joplin/keymap.json" ;;
    *) put "$item" "$HOME/.config/$name" ;;
  esac
done
[[ -f "$DOT/config/nvim/init.vim" ]] && put "$DOT/config/nvim/init.vim" "$HOME/.vimrc"

# fonts + desktop entries
put "$DOT/.local/share/fonts"        "$HOME/.local/share/fonts"
put "$DOT/.local/share/applications" "$HOME/.local/share/applications"
fc-cache -f >/dev/null 2>&1 || true

# his scripts -> ~/scripts (on PATH via his .zshenv); z.lua where his zshrc wants it
if [[ -d "$SCR" ]]; then
  log "Installing his scripts to ~/scripts..."
  rm -f "$SCR/joshuto"                                 # bundled binary; the joshuto package replaces it
  put "$SCR" "$HOME/scripts"
  find "$HOME/scripts" -type f ! -name '*.md' ! -name 'LICENSE*' ! -name '.gitignore' -exec chmod +x {} +
  mkdir -p "$HOME/.local/bin"
  [[ -f "$HOME/scripts/z.lua" ]] && cp -f "$HOME/scripts/z.lua" "$HOME/.local/bin/z.lua"
fi

# ---------- 7. build his st and dmenu ----------------------------------------
build_suckless() {
  local dir="$WORK/$1"
  [[ -d "$dir" ]] || return 0
  log "Building his $1..."
  ( cd "$dir" && make clean >/dev/null 2>&1 || true
    make && sudo make install ) || warn "$1 failed to build (check that libx11/libxft/libxinerama are installed)."
}
if [[ $SKIP_PKGS -eq 0 ]]; then
  build_suckless st
  build_suckless dmenu
fi

# ---------- 8. powerline-shell + login shell ---------------------------------
if [[ $SKIP_PKGS -eq 0 ]]; then
  log "Installing powerline-shell (his purple theme is in ~/.config/powerline-shell)..."
  pipx ensurepath >/dev/null 2>&1 || true
  pipx install powerline-shell >/dev/null 2>&1 || pipx upgrade powerline-shell >/dev/null 2>&1 || warn "powerline-shell install failed."
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]] && command -v zsh >/dev/null; then
    if confirm "Make zsh (his shell) your login shell?"; then chsh -s "$(command -v zsh)" || warn "chsh failed."; fi
  fi
  xdg-user-dirs-update >/dev/null 2>&1 || true
fi

# ---------- done --------------------------------------------------------------
echo
log "Done. WM: ${WM}   Terminal: st   Prompt: powerline-shell (purple)"
echo "  Backups of replaced files : ${BACKUP}"
[[ ${#MISSING_PKGS[@]} -gt 0 ]] && echo "  Not found in repo/AUR     : ${MISSING_PKGS[*]}"
[[ ${#FAILED_PKGS[@]}  -gt 0 ]] && echo "  Failed to install         : ${FAILED_PKGS[*]}"
echo "  Not applied on purpose    : his crontabs (dotfiles/cron) - they run his personal jobs."
echo "  Next                      : log out and log in on tty1; the session starts automatically."
