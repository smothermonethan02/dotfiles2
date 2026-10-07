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
#   ./script.sh --layout gb          # keyboard layout (default: us)
#   WEATHER_LOC="Fort+Wayne" ./script.sh   # city for the polybar weather module
#
# Inside i3, press Super+F1 to see every keybinding (Enter runs the selected one).
# Or just RIGHT-CLICK: on the desktop, on the bar, or on a window's title bar.
#
# Run as your normal user, NOT root. Every file it replaces is backed up first.
# =============================================================================
set -euo pipefail

# ---------- options -----------------------------------------------------------
ZIPDIR=""; ASSUME_YES=0; SKIP_PKGS=0; HEAVY=1
WEATHER_LOC="${WEATHER_LOC:-}"; KB_LAYOUT="us"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zips)          ZIPDIR="$2"; shift 2 ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    --no-packages)   SKIP_PKGS=1; shift ;;
    --no-heavy-apps) HEAVY=0; shift ;;
    --layout)        KB_LAYOUT="$2"; shift 2 ;;
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
  xorg-xwininfo xorg-xev xorg-xinput xorg-xmodmap xorg-setxkbmap xclip xsel xdotool
  libx11 libxft libxinerama fontconfig freetype2)
PKG_I3=(i3-wm polybar picom dunst libnotify feh betterlockscreen maim brightnessctl
  networkmanager network-manager-applet udiskie pacman-contrib lm_sensors sysstat
  pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol pulsemixer alsa-utils
  playerctl xdg-utils xdg-user-dirs qt5ct lxappearance imwheel flameshot rofi
  jgmenu xclickroot)
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
  if ! command -v xclickroot >/dev/null; then
    log "Building xclickroot (right-click on the desktop) from source..."
    tmp=$(mktemp -d)
    if git clone -q --depth 1 https://github.com/phillbush/xclickroot "$tmp/xclickroot"; then
      (cd "$tmp/xclickroot" && make && sudo make install) || warn "xclickroot failed to build; desktop right-click won't work (bar and title bars still will)."
    fi
    rm -rf "$tmp"
  fi
  sudo systemctl enable --now NetworkManager.service 2>/dev/null || true
  sudo pkgfile --update >/dev/null 2>&1 || true
  sudo sensors-detect --auto >/dev/null 2>&1 || true
  # keyboard layout for X and the text console
  sudo localectl set-x11-keymap "$KB_LAYOUT" 2>/dev/null || warn "Could not set the X keyboard layout to $KB_LAYOUT."
  sudo localectl set-keymap "$KB_LAYOUT" 2>/dev/null || true
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

# His standard i3 layout keys were commented out "for testing" -> on (none clash)
sed -i -e 's|^#\(bindsym \$mod+Shift+s layout stacking\)|\1|' \
       -e 's|^#\(bindsym \$mod+Shift+t layout tabbed\)|\1|' \
       -e 's|^#\(bindsym \$mod+Shift+i layout toggle split\)|\1|' \
       -e 's|^#\(bindsym \$mod+Shift+space floating toggle\)|\1|' \
       -e 's|^#\(bindsym \$mod+space focus mode_toggle\)|\1|' "$I3"
sed -i 's|^# Here for testing$|# Layouts and floating windows|' "$I3"
cat >> "$I3" <<'EOF'

###---Keybinding cheat sheet---###
bindsym $mod+F1 exec --no-startup-id i3keys

###---Right-click menu---###
# Right-click the empty desktop
exec --no-startup-id xclickroot -r rightmenu
# Right-click a window's title bar or border (picks that window first)
bindsym --release --border button3 focus; exec --no-startup-id rightmenu
# Keyboard: the menu key, or Super+Escape
bindsym Menu exec --no-startup-id rightmenu
bindsym $mod+Escape exec --no-startup-id rightmenu
EOF

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
# Menu button on the left, and right-click on any empty part of the bar
sed -i 's#^modules-left = i3 xwindow#modules-left = menu i3 xwindow#' "$PB"
sed -i 's#^\(cursor-scroll = .*\)$#\1\nclick-right = rightmenu \&#' "$PB"

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

[module/menu]
type = custom/text
format = " ☰ "
format-background = ${colors.background-wm}
format-underline = ${colors.primary}
click-left = rightmenu &
click-right = rightmenu &

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

# Super+F1: list every i3 keybinding in dmenu; Enter runs the one you pick
cat > "$SCR/i3keys" <<'I3KEYS'
#!/bin/sh
# i3keys - list every i3 keybinding in dmenu (Super+F1); pick one to run it.
cfg="${1:-$HOME/.config/i3/config}"
[ -f "$cfg" ] || { notify-send "i3keys" "No i3 config at $cfg"; exit 1; }

list=$(awk '
  function pretty(k) {
    gsub(/\$mod/, "Super", k); gsub(/Mod1/, "Alt", k); gsub(/Mod4/, "Super", k)
    gsub(/[Cc]ontrol/, "Ctrl", k); gsub(/shift/, "Shift", k); gsub(/control/, "Ctrl", k)
    return k
  }
  /^[ \t]*mode "/        { m = $2; gsub(/"/, "", m); d = ""; next }
  /^[ \t]*}/             { m = ""; d = ""; next }
  /^[ \t]*#[ \t]*(bindsym|exec|set|bar|font)/ { next }
  /^[ \t]*#/             { d = $0; sub(/^[ \t]*#+[- ]*/, "", d); sub(/[- #]*$/, "", d); next }
  /^[ \t]*bindsym /      {
    key = pretty($2)
    cmd = $0; sub(/^[ \t]*bindsym[ \t]+[^ \t]+[ \t]+/, "", cmd)
    shown = cmd; sub(/^exec (--no-startup-id )?/, "", shown)
    pre = (m != "") ? "[" m "] " : ""
    printf "%-26s %-48s %s\n", pre key, shown, (d != "" ? "# " d : "")
  }
  /^[ \t]*$/             { d = "" }
' "$cfg")

choice=$(printf '%s\n' "$list" | dmenu -i -l 25 -p "i3 keys (Enter runs it):") || exit 0
[ -z "$choice" ] && exit 0

key=$(printf '%s' "$choice" | awk '{print $1}')
case "$key" in \[*) exit 0 ;; esac          # mode-only keys can't run from here

# run the exact command from the config line
cmd=$(awk -v want="$key" '
  function pretty(k) {
    gsub(/\$mod/, "Super", k); gsub(/Mod1/, "Alt", k); gsub(/Mod4/, "Super", k)
    gsub(/[Cc]ontrol/, "Ctrl", k); gsub(/shift/, "Shift", k); gsub(/control/, "Ctrl", k)
    return k
  }
  /^[ \t]*mode "/ { inmode = 1 } /^[ \t]*}/ { inmode = 0 }
  !inmode && /^[ \t]*bindsym / && pretty($2) == want {
    c = $0; sub(/^[ \t]*bindsym[ \t]+[^ \t]+[ \t]+/, "", c); print c; exit
  }' "$cfg")
[ -n "$cmd" ] && i3-msg "$cmd" >/dev/null
I3KEYS

# Right-click menu (desktop / bar / title bars): everything the shortcuts do
cat > "$SCR/rightmenu" <<'RIGHTMENU'
#!/bin/sh
# rightmenu - right-click menu for i3 (desktop, polybar, window title bars)
# Only lists apps that are installed. Menu look: ~/.config/jgmenu/jgmenurc

has() { command -v "$1" >/dev/null 2>&1; }
term="${TERMINAL:-st}"
app() {   # app <label> <binary> <command...>
  label="$1"; bin="$2"; shift 2
  has "$bin" && printf '%s,%s\n' "$label" "$*"
}

menu() {
cat <<EOF
Terminal,$term
Run program...,dmenu_run
^sep()
Apps,^checkout(apps)
Files,^checkout(files)
Window,^checkout(window)
Workspaces,^checkout(workspaces)
Sound,^checkout(sound)
Screenshot,^checkout(shot)
^sep()
Web search...,sch "${BROWSER:-firefox}"
Update system,updatepackages
Keyboard shortcuts...,i3keys
^sep()
System,^checkout(system)
EOF

echo '^tag(apps)'
app "Firefox"          firefox     firefox
app "Brave"            brave       brave
app "Neovim"           nvim        "$term -e nvim"
app "VSCodium"         vscodium    vscodium
app "GIMP"             gimp        gimp
app "OBS Studio"       obs         obs
app "Kdenlive"         kdenlive    kdenlive
app "Blender"          blender     blender
app "Discord"          discord     discord
app "Spotify"          spotify-launcher spotify-launcher
app "Thunderbird"      thunderbird thunderbird
app "Music (ncmpcpp)"  ncmpcpp     "$term -e ncmpcpp"
app "Calendar"         calcurse    "$term -e calcurse"
app "RSS (newsboat)"   newsboat    "$term -e newsboat"
app "Torrents (tremc)" tremc       "$term -e tremc"
app "System monitor"   htop        "$term -e htop"
app "Tabbed terminal"  tabbed      stabmux

echo '^tag(files)'
app "Ranger"           ranger      "$term -e ranger"
app "PCManFM"          pcmanfm     pcmanfm
echo "Home folder,xdg-open $HOME"
echo "Screenshots folder,xdg-open $HOME/pictures/screenshots"

cat <<'EOF'
^tag(window)
Close window,i3-msg kill
Float / tile,i3-msg floating toggle
Fullscreen,i3-msg fullscreen toggle
^sep()
Layout: tabbed,i3-msg layout tabbed
Layout: stacked,i3-msg layout stacking
Layout: split,i3-msg layout toggle split
Split next window side by side,i3-msg split h
Split next window below,i3-msg split v
Resize mode (Esc to leave),i3-msg mode resize
^sep()
Send to workspace,^checkout(sendto)
EOF

echo '^tag(sendto)'
for n in 1 2 3 4 5 6 7 8 9 10; do
  echo "Workspace $n,i3-msg \"move container to workspace number $n; workspace number $n\""
done

echo '^tag(workspaces)'
for n in 1 2 3 4 5 6 7 8 9 10; do
  echo "Workspace $n,i3-msg workspace number $n"
done

cat <<'EOF'
^tag(sound)
Volume up,pulsevolctrl output-vol @DEFAULT_SINK@ +5%
Volume down,pulsevolctrl output-vol @DEFAULT_SINK@ -5%
Mute / unmute,pulsevolctrl output-mute @DEFAULT_SINK@
Mixer,${TERMINAL:-st} -e pulsemixer
Play / pause,playerctl play-pause
Next track,playerctl next
Previous track,playerctl previous
^tag(shot)
Whole screen,screenshot full
Select area,screenshot select
Whole screen after delay,screenshot fulltime
Area after delay,screenshot selecttime
^tag(system)
EOF
[ -x "$HOME/.local/bin/vmdisplay" ] && echo "Fit screen to window,$HOME/.local/bin/vmdisplay fit"
cat <<'EOF'
Lock screen,betterlockscreen -l
Reload i3 config,i3-msg reload
Restart i3,i3-msg restart
^sep()
Log out,prompt "Log out of i3?" "i3-msg exit"
Reboot,prompt "Reboot?" "systemctl reboot"
Shut down,prompt "Shut down?" "systemctl poweroff"
EOF
}

# a second right-click while the menu is open just closes it
pkill -x jgmenu && exit 0
menu | jgmenu --simple --at-pointer --config-file="$HOME/.config/jgmenu/jgmenurc"
RIGHTMENU

mkdir -p "$DOT/config/jgmenu"
cat > "$DOT/config/jgmenu/jgmenurc" <<'JGMENURC'
# Right-click menu, in Brodie's colours (from his .Xresources)
stay_alive          = 0
position_mode       = pointer
menu_width          = 230
menu_padding_top    = 6
menu_padding_right  = 6
menu_padding_bottom = 6
menu_padding_left   = 6
menu_border         = 2
menu_radius         = 0
item_height         = 26
item_padding_x      = 8
sep_height          = 5
font                = JetBrains Mono 10
arrow_string        = ›
sub_hover_action    = 1
color_menu_bg       = #1d1f21 100
color_menu_border   = #327bd1 100
color_norm_bg       = #1d1f21 0
color_norm_fg       = #d8dee9 100
color_sel_bg        = #327bd1 100
color_sel_fg        = #ffffff 100
color_sep_fg        = #444444 100
JGMENURC

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
setxkbmap KB_LAYOUT_PLACEHOLDER
mpd &
mpDris2 &
udiskie -t &
xset m 0 0
xsetroot -cursor_name left_ptr &

exec i3
EOF

sed -i "s/KB_LAYOUT_PLACEHOLDER/${KB_LAYOUT}/" "$DOT/.xinitrc"

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
# st: add the usual Ctrl+Shift+C / Ctrl+Shift+V copy-paste (his Ctrl+Y / Ctrl+V still work)
if [[ -f "$WORK/st/config.h" ]] && ! grep -q 'TERMMOD,[[:space:]]*XK_V' "$WORK/st/config.h"; then
  sed -i '/XK_Insert,[[:space:]]*selpaste/a\
\t{ TERMMOD,              XK_C,               clipcopy,       {.i =  0} },\
\t{ TERMMOD,              XK_V,               clippaste,      {.i =  0} },' "$WORK/st/config.h"
fi
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

# ---------- 10b. VM: make the desktop fill the VM window ---------------------
VIRT=$(systemd-detect-virt 2>/dev/null || true)
if [[ $SKIP_PKGS -eq 0 && -n "$VIRT" && "$VIRT" != none ]]; then
  if [[ -f "$SCRIPT_DIR/vm-display-fix.sh" ]]; then
    log "Running in a VM (${VIRT}) - fixing the screen size..."
    bash "$SCRIPT_DIR/vm-display-fix.sh" || warn "vm-display-fix.sh reported a problem."
  else
    warn "Running in a VM: put vm-display-fix.sh next to this script to fix the screen size."
  fi
fi

# ---------- 11. check the result ---------------------------------------------
# Old/wizard configs in ~/.i3 would be used if ~/.config/i3/config ever went missing
for old in "$HOME/.i3/config" "$HOME/.i3"; do
  if [[ -e "$old" ]]; then
    mkdir -p "$BACKUP"; mv "$old" "$BACKUP/$(basename "$old").old-i3" 2>/dev/null || true
    warn "Moved an old i3 config out of the way: $old"
  fi
done

# Make sure the i3 config in place really is Brodie's (fixed) one
if ! grep -q 'launchpolybar' "$HOME/.config/i3/config" 2>/dev/null; then
  warn "~/.config/i3/config isn't Brodie's - copying it in again."
  mkdir -p "$HOME/.config/i3"
  cp -f "$I3" "$HOME/.config/i3/config"
fi

if command -v i3 >/dev/null; then
  if i3 -C -c "$HOME/.config/i3/config" >/dev/null 2>&1; then log "i3 config check: OK"
  else warn "i3 config check reported problems:"; i3 -C -c "$HOME/.config/i3/config" || true; fi
  # If i3 is already running, restart it in place so the new keys load now
  if [[ -n "${DISPLAY:-}" ]] && pgrep -x i3 >/dev/null; then
    i3-msg restart >/dev/null 2>&1 && log "Restarted i3 with Brodie's keybindings."
  fi
fi

echo
log "Done.  WM: i3   Bar: his polybar   Terminal: st   Files: ranger   Prompt: purple powerline"
echo "  Keyboard                  : ${KB_LAYOUT} layout.  Super+F1 inside i3 lists every keybinding."
echo "  Mouse                     : right-click the desktop, the bar or a title bar for the menu."
echo "  Backups of replaced files : ${BACKUP}"
[[ ${#MISSING_PKGS[@]} -gt 0 ]] && echo "  Not found in repo/AUR     : ${MISSING_PKGS[*]}"
[[ ${#FAILED_PKGS[@]}  -gt 0 ]] && echo "  Failed to install         : ${FAILED_PKGS[*]}"
echo "  Not applied on purpose    : his crontabs (dotfiles/cron) - they run his personal jobs."
echo "  Next                      : log out, log in on tty1 - i3 and polybar start automatically."
