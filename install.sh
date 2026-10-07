[script (1).sh](https://github.com/user-attachments/files/33148657/script.1.sh)
#!/usr/bin/env bash
# =============================================================================
# script.sh - Brodie Robertson's i3 setup on Arch Linux
#
#   Window manager : HIS i3 config (fixed so every keybind works on your machine)
#   Bar            : HIS polybar config, converted from bspwm to i3 (replaces i3bar)
#   Terminal       : HIS st build      Launcher: HIS dmenu build
#   File manager   : ranger, with image/archive/media previews
#   Prompt         : HIS purple powerline-shell theme (zsh + bash)
#   Plus           : his scripts (~/scripts), nvim + plugins, dunst, mpv, zsh,
#                    GTK/Qt themes, fonts and the rest of his dotfiles
#
#   Uses the four repo zips (next to this script, in ~/Downloads, or --zips DIR):
#     dotfiles-master*.zip  scripts-master*.zip  st-master*.zip  dmenu-master*.zip
#   Any zip it can't find is downloaded from the Internet Archive / GitHub.
#
# Usage:
#   chmod +x script.sh
#   ./script.sh                      # full install
#   ./script.sh --zips ~/somewhere   # folder holding the zips
#   ./script.sh -y                   # no confirmation prompts
#   ./script.sh --no-heavy-apps      # skip GIMP/OBS/Kdenlive/Blender/VSCodium/Brave/...
#   ./script.sh --no-packages        # only apply configs (no pacman/yay, no builds)
#   WEATHER_LOC="Fort+Wayne" ./script.sh   # city for the polybar weather module
#
# Run as your normal user, NOT root. Every file it replaces is backed up first.
# =============================================================================
set -euo pipefail

# ---------- options -----------------------------------------------------------
ZIPDIR=""; ASSUME_YES=0; SKIP_PKGS=0; HEAVY=1
WEATHER_LOC="${WEATHER_LOC:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zips)          ZIPDIR="$2"; shift 2 ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    --no-packages)   SKIP_PKGS=1; shift ;;
    --no-heavy-apps) HEAVY=0; shift ;;
    -h|--help)       sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1  (try --help)" >&2; exit 1 ;;
  esac
done

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

# ---------- package lists -----------------------------------------------------
# Everything his i3 config, polybar modules, scripts, shell config and ranger use.
PKG_CORE=(base-devel git curl wget unzip rsync python python-pipx lua ruby perl jq bc
  zsh zsh-syntax-highlighting zsh-you-should-use pkgfile
  xorg-server xorg-xinit xorg-xsetroot xorg-xset xorg-xrdb xorg-xrandr xorg-xprop
  xorg-xwininfo xorg-xev xorg-xinput xorg-xmodmap xclip xsel xdotool
  libx11 libxft libxinerama fontconfig freetype2)
PKG_I3=(i3-wm polybar picom dunst libnotify feh betterlockscreen maim brightnessctl
  networkmanager network-manager-applet udiskie pacman-contrib lm_sensors sysstat
  pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol pulsemixer alsa-utils
  playerctl xdg-utils xdg-user-dirs qt5ct lxappearance imwheel flameshot rofi)
PKG_RANGER=(ranger w3m python-pillow highlight atool p7zip unrar libarchive mediainfo
  poppler ffmpegthumbnailer perl-image-exiftool odt2txt imagemagick python-chardet)
PKG_CLI=(neovim nodejs npm fzf ripgrep eza trash-cli htop btop neofetch fastfetch
  broot calcurse newsboat tmux tabbed glow pandoc-cli acpi speedtest-cli prettyping
  php v4l-utils dragon-drop simple-mtpfs cointop transmission-cli tremc)
PKG_MEDIA=(mpv mpd ncmpcpp mpdris2 zathura zathura-pdf-mupdf nsxiv)
PKG_FONTS=(adobe-source-code-pro-fonts ttf-jetbrains-mono ttf-hack-nerd otf-ipafont
  ttf-symbola ttf-roboto noto-fonts noto-fonts-emoji ttf-font-awesome powerline-fonts)
PKG_GUI=(firefox rxvt-unicode pcmanfm)
PKG_HEAVY=(gimp obs-studio kdenlive blender vscodium-bin brave-bin thunderbird
  discord spotify-launcher joplin)

FAILED_PKGS=(); MISSING_PKGS=()
install_pkgs() {     # sorts names into official repo / AUR / not found, then installs
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
  log "Updating the system and installing build tools..."
  sudo pacman -Syu --needed --noconfirm base-devel git curl unzip

  if ! command -v yay >/dev/null; then
    log "Bootstrapping yay (AUR helper)..."
    tmp=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
  fi

  log "Installing i3, polybar, ranger and the rest of his stack..."
  install_pkgs "${PKG_CORE[@]}" "${PKG_I3[@]}" "${PKG_RANGER[@]}" "${PKG_CLI[@]}" \
               "${PKG_MEDIA[@]}" "${PKG_FONTS[@]}" "${PKG_GUI[@]}"
  if [[ $HEAVY -eq 1 ]] && confirm "Also install the big apps his i3 keybinds open (GIMP, OBS, Kdenlive, Blender, VSCodium, Brave, Thunderbird, Discord, Spotify, Joplin)?"; then
    install_pkgs "${PKG_HEAVY[@]}"
  fi
  sudo systemctl enable --now NetworkManager.service 2>/dev/null || true
  sudo pkgfile --update >/dev/null 2>&1 || true
  sudo sensors-detect --auto >/dev/null 2>&1 || true
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
      log "Downloaded ${gh}"; unpack_zip "$WORK/$name.zip" "$name" && return 0
    fi
  done
  git clone --depth 1 "https://github.com/${gh}.git" "$WORK/$name" && rm -rf "$WORK/$name/.git" && return 0
  return 1
}

get_repo dotfiles "dotfiles-master*.zip" BrodieRobertson/dotfiles || die "Could not get the dotfiles."
get_repo scripts  "scripts-master*.zip"  BrodieRobertson/scripts  || die "Could not get his scripts (polybar needs them)."
get_repo st       "st-master*.zip"       BrodieRobertson/st       || warn "Could not get his st; skipping it."
get_repo dmenu    "dmenu-master*.zip"    BrodieRobertson/dmenu    || warn "Could not get his dmenu; skipping it."

DOT="$WORK/dotfiles"; SCR="$WORK/scripts"
I3="$DOT/config/i3/config"; PB="$DOT/config/polybar/config"
[[ -f "$I3" ]] || die "His i3 config is missing from the dotfiles zip."
[[ -f "$PB" ]] || die "His polybar config is missing from the dotfiles zip."

# ---------- 3. clean up machine-specific bits --------------------------------
log "Fixing paths and links that only worked on his machine..."

# Symlinks into /home/brodie/repos/dotfiles -> real copies; other absolute links removed
for tree in "$DOT" "$SCR"; do
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

# His caches / history / personal state
rm -rf "$DOT/config/mpv/watch_later" "$DOT/config/transmission-daemon/"settings.json.tmp.* \
       "$DOT/.calcurse/.calcurse.pid" "$DOT/config/vifm/vifminfo" "$DOT/config/vifm/vifminfo.json" \
       "$DOT/config/nvim/.netrwhist" "$DOT/config/bashtop/error.log" "$DOT/.zcompdump" \
       "$DOT/config/flameshot/flameshot.inio" "$DOT/config/mpd/database" \
       "$DOT/config/blender/"*/config/recent-files.txt 2>/dev/null || true
rm -f "$SCR/joshuto"     # prebuilt binary; the joshuto package replaces it

# /home/brodie -> your home, in every text file
for tree in "$DOT" "$SCR"; do
  grep -rIl --null '/home/brodie' "$tree" 2>/dev/null | xargs -0 -r sed -i "s#/home/brodie#${HOME}#g"
done

# Neovim plugins are git submodules, so the zip has them empty: fetch them
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

# ---------- 4. his i3 config, fixed ------------------------------------------
log "Fixing his i3 config..."

# i3bar -> his polybar
sed -i '/^bar {/,/^}/d' "$I3"
sed -i 's|^# Status Bar$|# Status Bar (his polybar)\nexec_always --no-startup-id ~/scripts/polybar/launchpolybar|' "$I3"

# Autostart: drop things that only existed on his machine
sed -i -e 's|^exec --no-startup-id transmission-rss -f|# & (needs his transmission-rss feed setup)|' \
       -e 's|^exec --no-startup-id xinput set-prop 11 295 1.9|# & (device IDs from his mouse)|' "$I3"
cat >> "$I3" <<'EOF'

###---Added by script.sh---###
# Lock-screen image cache for betterlockscreen ($mod+Shift+b)
exec --no-startup-id sh -c '[ -d ~/.cache/betterlockscreen ] || betterlockscreen -u ~/.config/wall.png'
# Media keys (sxhkd handled these on his bspwm setup)
bindsym XF86AudioRaiseVolume exec --no-startup-id pulsevolctrl output-vol @DEFAULT_SINK@ +2%
bindsym XF86AudioLowerVolume exec --no-startup-id pulsevolctrl output-vol @DEFAULT_SINK@ -2%
bindsym XF86AudioMute exec --no-startup-id pulsevolctrl output-mute @DEFAULT_SINK@
bindsym XF86AudioPlay exec --no-startup-id playerctl play-pause
bindsym XF86AudioNext exec --no-startup-id playerctl next
bindsym XF86AudioPrev exec --no-startup-id playerctl previous
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +5%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%-
bindsym Print exec --no-startup-id screenshot full
bindsym Shift+Print exec --no-startup-id screenshot select
EOF

# Volume: his 'volctrl' isn't in his scripts repo -> his pulsevolctrl (works with PipeWire)
sed -i -E \
  -e 's#exec volctrl (Headphone|Master) 2%\+#exec --no-startup-id pulsevolctrl output-vol @DEFAULT_SINK@ +2%#' \
  -e 's#exec volctrl (Headphone|Master) 2%-#exec --no-startup-id pulsevolctrl output-vol @DEFAULT_SINK@ -2%#' \
  -e 's#exec volctrl All mute#exec --no-startup-id pulsevolctrl output-mute @DEFAULT_SINK@#' "$I3"

# Brightness: 'light' is gone from the Arch repos -> brightnessctl
sed -i -e 's#exec light -A 5 && pkill -SIGRTMIN+4 i3block#exec --no-startup-id brightnessctl set +5%#' \
       -e 's#exec light -U 5 && pkill -SIGRTMIN+4 i3block#exec --no-startup-id brightnessctl set 5%-#' "$I3"

# Reboot / shutdown without sudo ('sudo shutdown' alone also waits a minute)
sed -i -e 's#"sudo reboot"#"systemctl reboot"#' -e 's#"sudo shutdown"#"systemctl poweroff"#' "$I3"

# Renamed scripts
sed -i -e 's#exec scrnshot #exec --no-startup-id screenshot #' -e 's#exec toggleTouch#exec --no-startup-id toggletouch#' "$I3"

# Keybinds for scripts that are NOT in his public scripts repo -> disabled
for s in mntandroid importandroid devenv timer openterminalin 'bm "firefox"' multimonitor; do
  sed -i "s#^\(bindsym [^ ]* exec ${s}\)\$#\# \1   (script or a helper it needs is not in his public repo)#" "$I3"
done

# Programs: Ubuntu/snap-era launchers -> Arch equivalents; lf -> ranger
sed -i -e 's#exec snap run spotify#exec spotify-launcher#' \
       -e 's#exec apulse discord#exec discord#' \
       -e 's#^\(bindsym \$mod+Mod1+l exec snap run slack\)#\# \1   (Slack: install slack-desktop and re-enable)#' \
       -e 's#^\(bindsym \$mod+Mod1+i exec virtualbox\)#\# \1   (install virtualbox and re-enable)#' \
       -e 's#exec dolphin#exec pcmanfm#' \
       -e 's#exec st -e lf#exec st -e ranger#' \
       -e 's#exec st -e transmission-remote-cli#exec st -e tremc#' \
       -e 's#exec i3-sensible-terminal#exec st#' "$I3"

# ---------- 5. his polybar config, converted to i3 ---------------------------
log "Converting his polybar config from bspwm to i3..."

sed -i -e 's#^monitor = \${env:MONITOR:DisplayPort-0}#monitor = ${env:MONITOR:}#' \
       -e 's#^wm-restack = bspwm#wm-restack = i3#' \
       -e 's#^modules-left = bspwm xwindow#modules-left = i3 xwindow#' \
       -e 's#^font-0 = .*#font-0 = "JetBrains Mono:style=Medium:pixelsize=10;2"#' \
       -e 's#^font-1 = .*#font-1 = "Hack Nerd Font:pixelsize=10;2"#' \
       -e 's#^font-2 = .*#font-2 = "Noto Color Emoji:scale=10;2"#' \
       -e 's#^font-3 = .*#font-3 = "IPAGothic:pixelsize=10;2"#' "$PB"

# Tray: tray-position is deprecated in polybar 3.7 -> tray module, same look
sed -i -e '/^tray-position = /d' -e '/^tray-padding = /d' -e '/^tray-background = /d' \
       -e '/^tray-offset-[xy] = /d' -e '/^tray-scale = /d' "$PB"
sed -i 's#^\(modules-right = .*time\)$#\1 tray#' "$PB"

# pacman module ran 'sudo pacman -Qu' (asks for a password the bar can't give) -> checkupdates
awk -v loc="$WEATHER_LOC" '
  /^\[module\/pacman-packages\]/ { skip=1; print; print "type = custom/script"; print "exec = checkupdates 2>/dev/null | wc -l"; print "interval = 1800"; print "format-prefix = \"📦 \""; print "click-left = updatepackages &"; print ""; next }
  /^\[module\/volume\]/          { skip=1; print; print "type = custom/ipc"; print "hook-0 = polypulsevolume"; print "initial = 1"; print "click-left = $TERMINAL -e pulsemixer &"; print "click-right = pulsevolctrl output-mute @DEFAULT_SINK@"; print "scroll-up = pulsevolctrl output-vol @DEFAULT_SINK@ +2%"; print "scroll-down = pulsevolctrl output-vol @DEFAULT_SINK@ -2%"; print ""; next }
  /^\[module\/weather\]/         { skip=1; print; print "type = custom/script"; print "exec = i3weather"; print "label = \"%output%\""; print "click-left = $TERMINAL -e sh -c \"curl -s wttr.in/" loc "; read -r _\" &"; print "interval = 1800"; print ""; next }
  /^\[/                          { skip=0 }
  !skip
' "$PB" > "$PB.new" && mv "$PB.new" "$PB"

# i3 workspaces module, styled exactly like his bspwm one
cat >> "$PB" <<'EOF'

[module/i3]
type = internal/i3
pin-workspaces = true
index-sort = true
enable-click = true
enable-scroll = true
wrapping-scroll = false

label-focused = %name%
label-focused-background = ${colors.background-wm}
label-focused-underline = ${colors.primary}
label-focused-padding = 1

label-unfocused = %name%
label-unfocused-padding = 1

label-visible = %name%
label-visible-padding = 1

label-urgent = %name%!
label-urgent-background = ${colors.alert}
label-urgent-padding = 1

label-mode = %mode%
label-mode-background = ${colors.alert}
label-mode-padding = 1

format-underline = ${colors.background}
format-background = ${colors.background}
format-padding =

; Separator in between workspaces
label-separator = |

[module/tray]
type = internal/tray
tray-padding = 1
tray-background = ${colors.background-alt}
format-underline = ${colors.background}
EOF

# ---------- 6. fix his polybar / i3 helper scripts ---------------------------
log "Fixing the scripts his bar and keybinds call..."

# One bar per monitor, logs to /tmp for troubleshooting
cat > "$SCR/polybar/launchpolybar" <<'EOF'
#!/bin/sh
# Launches his polybar on every connected monitor
killall -q polybar
while pgrep -u "$(id -u)" -x polybar >/dev/null; do sleep 0.2; done
for m in $(polybar --list-monitors | cut -d: -f1); do
  MONITOR=$m polybar --reload bar >>"/tmp/polybar-$m.log" 2>&1 &
done
EOF

# Volume readout: was hard-wired to his sound card (pci-0000_0b) -> default output
cat > "$SCR/polybar/polypulsevolume" <<'EOF'
#!/bin/sh
# Outputs the default output's volume, formatted for polybar
mute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}')
vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]*%' | head -n1)
[ -z "$vol" ] && { echo "🔈 n/a"; exit 0; }
n=$(echo "$vol" | tr -d '%')
if   [ "$mute" = "yes" ]; then echo "🔇 mute"
elif [ "$n" -gt 70 ];     then echo "🔊 $vol"
elif [ "$n" -gt 35 ];     then echo "🔉 $vol"
else                           echo "🔈 $vol"
fi
EOF

cat > "$SCR/pulse/pulsevolctrl" <<'EOF'
#!/bin/sh
# pulsevolctrl output-vol <sink> <+N%|-N%>   |   pulsevolctrl output-mute <sink>
# Changes the volume and refreshes the polybar volume module
sink="${2:-@DEFAULT_SINK@}"
if [ "$1" = "output-vol" ]; then
  pactl set-sink-mute "$sink" false
  pactl set-sink-volume "$sink" "$3"
else
  pactl set-sink-mute "$sink" toggle
fi
polybar-msg action "#volume.hook.0" >/dev/null 2>&1 || true
EOF

# CPU temp: only knew AMD Zen 1 'Tdie' -> also Tctl (newer AMD) and Intel/other
cat > "$SCR/polybar/polytempamd" <<'EOF'
#!/bin/sh
# CPU temperature formatted for polybar (AMD Tdie/Tctl, Intel Package, generic)
temp=$(sensors 2>/dev/null | awk '/^(Tdie|Tctl|Package id 0|CPU|Core 0|edge):/ {gsub(/[+°C]/,"",$0); for(i=1;i<=NF;i++) if($i ~ /^[0-9]+(\.[0-9]+)?$/){print $i; exit}}')
[ -z "$temp" ] && { echo "n/a"; exit 0; }
t=${temp%.*}
if   [ "$t" -gt 80 ]; then printf '%%{F#ed0b0b}'
elif [ "$t" -gt 60 ]; then printf '%%{F#f2e421}'
fi
echo "${temp}°C"
EOF

# Weather: was hard-coded to Adelaide -> your location (auto, or WEATHER_LOC)
cat > "$SCR/i3/i3weather" <<EOF
#!/bin/sh
# Current weather for polybar; set WEATHER_LOC (e.g. Fort+Wayne) to pick a city
loc="\${WEATHER_LOC:-${WEATHER_LOC}}"
w=\$(curl -fs --max-time 10 "wttr.in/\${loc}?format=%c+%t" 2>/dev/null)
case "\$w" in ""|*Unknown*|*html*|*HTML*) echo "WEATHER UNAVAILABLE" ;; *) echo "\$w" ;; esac
EOF

# CPU usage: forced the en_US locale, which most installs don't generate
sed -i 's#\$ENV{LC_ALL}="en_US";#$ENV{LC_ALL}="C";#' "$SCR/polybar/polycpu"

# Updates: -Su without a sync, and the window closed before you could read it
cat > "$SCR/updatepackages" <<'EOF'
#!/bin/sh
# Opens a terminal to update the system (bar count refreshes on its next check)
${TERMINAL:-st} -e sh -c 'sudo pacman -Syu; printf "\nDone - press Enter to close "; read -r _'
EOF

# Search menu ($mod+s) needs a list of engines, which isn't in the repo
mkdir -p "$DOT/config/search"
[[ -f "$DOT/config/search/search" ]] || cat > "$DOT/config/search/search" <<'EOF'
duckduckgo:duckduckgo.com/?q=
google:google.com/search?q=
youtube:youtube.com/results?search_query=
archwiki:wiki.archlinux.org/index.php?search=
aur:aur.archlinux.org/packages?K=
github:github.com/search?q=
EOF
touch "$DOT/config/search/search_history"

# ---------- 7. session, shell and app config fixes ---------------------------
log "Setting up the i3 session and shell..."

# Clean xinitrc for i3. His version also started sxhkd (whose binds would fire
# twice alongside i3's), nm-applet/transmission twice, and loaded xrdb in the
# background (polybar reads its colours from xrdb, so that has to finish first).
cat > "$DOT/.xinitrc" <<'EOF'
#!/bin/sh
# Brodie's autostart, cleaned up for i3
export PATH="$HOME/scripts:$HOME/scripts/alsa:$HOME/scripts/dragon:$HOME/scripts/lf:$HOME/scripts/i3:$HOME/scripts/pulse:$HOME/scripts/polybar:$HOME/scripts/bspwm:$HOME/scripts/lemonbar:$HOME/scripts/transmission:$HOME/.local/bin:$PATH"
export TERMINAL=st BROWSER=firefox EDITOR=nvim

[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources
mpd &
mpDris2 &
udiskie -t &
xset m 0 0
xsetroot -cursor_name left_ptr &

exec i3
EOF

START_CMD='pgrep -x i3 >/dev/null || startx "$XDG_CONFIG_HOME/X11/xinitrc"'
[[ -f "$DOT/.zprofile" ]] && sed -i "s#pgrep Hyprland || Hyprland#${START_CMD//&/\\&}#" "$DOT/.zprofile"
if [[ -f "$DOT/.profile" ]]; then
  sed -i "s#pgrep bspwm || startx .*#${START_CMD//&/\\&}#" "$DOT/.profile"
  sed -i -e 's#\. ~/\.config/bashrc#. ~/.bashrc#' -e 's/^export WM="bspwm"/export WM="i3"/' "$DOT/.profile"
fi

if [[ -f "$DOT/.zshenv" ]]; then
  sed -i -e 's/^export WM=.*/export WM="i3"/' \
         -e 's/^export TERMINAL=.*/export TERMINAL="st"/' \
         -e 's/^export LAUNCHER=.*/export LAUNCHER="dmenu_run"/' \
         -e 's/^export BROWSER=.*/export BROWSER="firefox"/' \
         -e 's/^export PAGER="moar"/export PAGER="less"/' \
         -e "s/^export \(GTK_IM_MODULE\|QT_IM_MODULE\|SDL_IM_MODULE\|XMODIFIERS\)=/# &/" \
         -e 's#"\$HOME/picures"#"$HOME/pictures"#' "$DOT/.zshenv"
fi

# Shell aliases: doas -> sudo if you don't use doas; vim alias pointed at a missing vimrc
if [[ -d "$DOT/config/shellconfig" ]]; then
  command -v doas >/dev/null || sed -i 's/\bdoas\b/sudo/g' "$DOT/config/shellconfig/"*
  sed -i "s#^alias vim='vim -u \"\$XDG_CONFIG_HOME/vim/vimrc\"'#alias vim='nvim'#" "$DOT/config/shellconfig/"*
fi

# dunst: his dmenu lives in /usr/local/bin and Brave may not be installed
if [[ -f "$DOT/config/dunst/dunstrc" ]]; then
  sed -i -e 's#^\(\s*dmenu = \)/usr/bin/dmenu#\1dmenu#' -e 's#^\(\s*browser = \)/usr/bin/brave#\1/usr/bin/xdg-open#' \
    "$DOT/config/dunst/dunstrc"
fi

# Prompt: bash -> his commented-out powerline block on, starship off
if [[ -f "$DOT/.bashrc" ]]; then
  sed -i '/---Powerline Prompt---/,/^# -----/{/^# -/!s/^#//}' "$DOT/.bashrc"
  sed -i 's/^eval "\$(starship init bash)"/# &/' "$DOT/.bashrc"
  sed -i -E 's#^source ([^ ]+)$#[ -f \1 ] \&\& source \1#' "$DOT/.bashrc"
fi
# zsh -> powerline-shell instead of spaceship
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
[[ -f "$DOT/config/powerline-shell/config.json" ]] && \
  sed -i "s#\"~/.config/powerline-shell/theme.py\"#\"${HOME}/.config/powerline-shell/theme.py\"#" "$DOT/config/powerline-shell/config.json"

# ---------- 8. apply everything ----------------------------------------------
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

for f in .bash_profile .bashrc .profile .Xresources .xinitrc .Xmodmap .imwheelrc .zprofile .zshenv .zshrc .calcurse; do
  put "$DOT/$f" "$HOME/$f"
done
chmod +x "$HOME/.xinitrc"
put "$DOT/.zshrc"       "$HOME/.config/zsh/.zshrc"       # his .zshenv sets ZDOTDIR=~/.config/zsh
put "$DOT/.zprofile"    "$HOME/.config/zsh/.zprofile"
put "$DOT/.xinitrc"     "$HOME/.config/X11/xinitrc"
put "$DOT/.Xresources"  "$HOME/.config/X11/xresources"
put "$DOT/.Xmodmap"     "$HOME/.config/X11/xmodmap"

for item in "$DOT"/config/*; do
  name=$(basename "$item")
  case "$name" in
    X11|zsh) ;;
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

put "$DOT/.local/share/fonts"        "$HOME/.local/share/fonts"
put "$DOT/.local/share/applications" "$HOME/.local/share/applications"
fc-cache -f >/dev/null 2>&1 || true

log "Installing his scripts to ~/scripts..."
put "$SCR" "$HOME/scripts"
find "$HOME/scripts" -type f ! -name '*.md' ! -name 'LICENSE*' ! -name '.gitignore' -exec chmod +x {} +
mkdir -p "$HOME/.local/bin"
[[ -f "$HOME/scripts/z.lua" ]] && cp -f "$HOME/scripts/z.lua" "$HOME/.local/bin/z.lua"

# Folders his configs write into
mkdir -p "$HOME/.cache/zsh" "$HOME/.local/share/zsh" "$HOME/.local/share/bash" \
         "$HOME/.local/share/mpd/playlists" "$HOME/music" "$HOME/pictures/screenshots"

# ranger: his rc.conf + rifle.conf, plus the preview script it expects
if command -v ranger >/dev/null; then
  [[ -f "$HOME/.config/ranger/scope.sh" ]] || ranger --copy-config=scope >/dev/null 2>&1 || true
  chmod +x "$HOME/.config/ranger/scope.sh" 2>/dev/null || true
fi

# ---------- 9. build his st and dmenu ----------------------------------------
build_suckless() {
  local dir="$WORK/$1"
  [[ -d "$dir" ]] || return 0
  log "Building his $1..."
  ( cd "$dir" && rm -f -- *.o "$1"
    make && sudo make install ) || warn "$1 failed to build (needs libx11, libxft, libxinerama)."
}
if [[ $SKIP_PKGS -eq 0 ]]; then
  build_suckless st
  build_suckless dmenu
fi

# ---------- 10. powerline-shell + login shell --------------------------------
if [[ $SKIP_PKGS -eq 0 ]]; then
  log "Installing powerline-shell (his purple theme is in ~/.config/powerline-shell)..."
  pipx ensurepath >/dev/null 2>&1 || true
  pipx install powerline-shell >/dev/null 2>&1 || pipx upgrade powerline-shell >/dev/null 2>&1 \
    || warn "powerline-shell install failed."
  if command -v zsh >/dev/null && [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
    if confirm "Make zsh (his shell) your login shell?"; then chsh -s "$(command -v zsh)" || warn "chsh failed."; fi
  fi
  xdg-user-dirs-update >/dev/null 2>&1 || true
fi

# ---------- 11. check the result ---------------------------------------------
if command -v i3 >/dev/null; then
  if i3 -C -c "$HOME/.config/i3/config" >/dev/null 2>&1; then log "i3 config check: OK"
  else warn "i3 config check reported problems:"; i3 -C -c "$HOME/.config/i3/config" || true; fi
fi

echo
log "Done.  WM: i3   Bar: his polybar   Terminal: st   Files: ranger   Prompt: purple powerline"
echo "  Backups of replaced files : ${BACKUP}"
[[ ${#MISSING_PKGS[@]} -gt 0 ]] && echo "  Not found in repo/AUR     : ${MISSING_PKGS[*]}"
[[ ${#FAILED_PKGS[@]}  -gt 0 ]] && echo "  Failed to install         : ${FAILED_PKGS[*]}"
echo "  Not applied on purpose    : his crontabs (dotfiles/cron) - they run his personal jobs."
echo "  Next                      : log out, log in on tty1 - i3 and polybar start automatically."
