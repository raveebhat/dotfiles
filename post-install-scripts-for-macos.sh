#!/usr/bin/env bash
set -euo pipefail

# post-install-mac-with-ghostty-colored-loginitems.sh
# Updated: prints where it will write the full log BEFORE asking permission.
# Functionality:
#  - installs Homebrew (if needed)
#  - installs requested apps (via brew / casks)
#  - installs starship, sets bash (Homebrew) as default shell
#  - installs xbar + net-speed.2s.sh plugin, adds xbar & itsycal to Login Items and launches them
#  - attempts to install Consolas (via homebrew/cask-fonts), warns if unavailable
#  - patches Ghostty config in ~/Library/Application Support/ghostty/config
#  - colorised terminal output: green=success, red=failure, yellow=warning
#  - writes full raw output & per-task logs to: ~/post_install_report.txt (printed before prompt)

LOGFILE="$HOME/post_install_report.txt"

# Print where we will write output BEFORE prompting
echo
echo "This script will write full raw command output and a task-by-task report to:"
echo "  $LOGFILE"
echo "You can inspect this file after the run. The script will append to the file."
echo

# ANSI colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"   # visible warning color
BLUE="\033[0;34m"
BOLD="\033[1m"
RESET="\033[0m"

echo "Run started at: $(date)" | tee -a "$LOGFILE"

# arrays for results
SUCCESS=()
FAILURE=()
WARNINGS=()

# helpers for logging/printing (color terminal + append plain to logfile)
log_info() {
  local msg="$1"
  printf "${BLUE}%s${RESET}\n" "$msg"
  printf "[%s] INFO: %s\n" "$(date '+%F %T')" "$msg" >> "$LOGFILE"
}
log_success() {
  local msg="$1"
  printf "${GREEN}%s${RESET}\n" "$msg"
  printf "[%s] SUCCESS: %s\n" "$(date '+%F %T')" "$msg" >> "$LOGFILE"
}
log_fail() {
  local msg="$1"
  printf "${RED}%s${RESET}\n" "$msg"
  printf "[%s] FAILURE: %s\n" "$(date '+%F %T')" "$msg" >> "$LOGFILE"
}
log_warn() {
  local msg="$1"
  printf "${YELLOW}%s${RESET}\n" "$msg"
  printf "[%s] WARNING: %s\n" "$(date '+%F %T')" "$msg" >> "$LOGFILE"
}

# helper to run a command, capture output to logfile, and record success/failure
run_and_log() {
  # args: <task-name> <command...>
  local task="$1"; shift
  printf "\n${BOLD}>>> START TASK: %s${RESET}\n" "$task" | tee -a "$LOGFILE"
  if "$@" >>"$LOGFILE" 2>&1; then
    log_success "TASK SUCCESS: $task"
    SUCCESS+=("$task")
    return 0
  else
    log_fail "TASK FAILED: $task (see $LOGFILE for details)"
    FAILURE+=("$task")
    return 1
  fi
}

# prompt once [Y/n] AFTER showing logfile location above
read -r -p "Proceed with installations and config changes? [Y/n]: " PROCEED
case "$PROCEED" in
  "" | [Yy]* ) log_info "User accepted, continuing..." ;;
  * ) log_info "Aborted by user."; exit 0 ;;
esac

# ---------- Packages ----------
CASKS=(
  ghostty
  localsend
  xbar
  vlc
  brave-browser
  duckduckgo
  firefox
  telegram
  sublime-text
  itsycal
  onlyoffice
  transmission
)
FORMULAE=(
  starship
  bash
)

PLUGINS_DIR="$HOME/Library/Application Support/xbar/plugins"
PLUGIN_NAME="net-speed.2s.sh"
PLUGIN_PATH="$PLUGINS_DIR/$PLUGIN_NAME"

# Ghostty config in Application Support (as requested)
GHOSTTY_AS_APP_SUPPORT_DIR="$HOME/Library/Application Support/ghostty"
GHOSTTY_CONFIG_PATH="$GHOSTTY_AS_APP_SUPPORT_DIR/config"

# ---------- Ensure Homebrew ----------
if ! command -v brew >/dev/null 2>&1; then
  run_and_log "Install Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  if [ -d /opt/homebrew/bin ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)" || true
  elif [ -d /usr/local/bin ]; then
    eval "$(/usr/local/bin/brew shellenv)" || true
  fi
else
  log_info "Homebrew already present"
  printf "[%s] Homebrew present\n" "$(date '+%F %T')" >> "$LOGFILE"
fi

run_and_log "brew update" brew update || true

# ---------- Install formulae ----------
for f in "${FORMULAE[@]}"; do
  if brew list "$f" >/dev/null 2>&1; then
    log_info "$f already installed"
    SUCCESS+=("formula:$f")
  else
    run_and_log "brew install $f" brew install "$f" || true
  fi
done

# ---------- Install casks ----------
for c in "${CASKS[@]}"; do
  if brew list --cask "$c" >/dev/null 2>&1; then
    log_info "cask $c already installed"
    SUCCESS+=("cask:$c")
  else
    run_and_log "brew install --cask $c" brew install --cask "$c" || true
  fi
done

# ---------- Set default shell to Homebrew bash ----------
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /usr/local)"
BREW_BASH="$BREW_PREFIX/bin/bash"

if [ -x "$BREW_BASH" ]; then
  if ! grep -qF "$BREW_BASH" /etc/shells 2>/dev/null; then
    run_and_log "Add $BREW_BASH to /etc/shells" sudo sh -c "echo $BREW_BASH >> /etc/shells"
  else
    log_info "$BREW_BASH already listed in /etc/shells"
  fi

  CUR_SHELL=$(dscl . -read ~/ UserShell 2>/dev/null | awk '{print $2}' || echo "$SHELL")
  if [ "$CUR_SHELL" != "$BREW_BASH" ]; then
    run_and_log "Change default shell to Homebrew bash" chsh -s "$BREW_BASH" || true
  else
    log_info "Default shell already $BREW_BASH"
    SUCCESS+=("chsh:already")
  fi
else
  log_fail "Homebrew bash not found at $BREW_BASH"
  FAILURE+=("brew-bash-not-found")
fi

# ---------- Starship init in bash profile ----------
BASH_PROFILE="$HOME/.bash_profile"
BASH_RC="$HOME/.bashrc"
if ! grep -q "starship init bash" "$BASH_PROFILE" 2>/dev/null; then
  echo 'eval "$(starship init bash)"' >> "$BASH_PROFILE" 2>>"$LOGFILE" || true
  log_info "Appended starship init to $BASH_PROFILE"
  SUCCESS+=("starship-init-appended:$BASH_PROFILE")
else
  log_info "starship init already in $BASH_PROFILE"
fi
if [ -f "$BASH_RC" ] && ! grep -q "starship init bash" "$BASH_RC" 2>/dev/null; then
  echo 'eval "$(starship init bash)"' >> "$BASH_RC" 2>>"$LOGFILE" || true
  log_info "Appended starship init to $BASH_RC"
  SUCCESS+=("starship-init-appended:$BASH_RC")
fi

# ---------- Write starship config ----------
mkdir -p "$(dirname "$HOME/.config/starship.toml")"
cat > "$HOME/.config/starship.toml" <<'STAREOF'
# Starship config installed by post-install script
add_newline = false
format = "$directory$git_branch$character"

[directory]
truncation_length = 3

[git_branch]
symbol = "🌱 "
style = "yellow"

[character]
success_symbol = "[→](bold green)"
error_symbol = "[←](bold red)"
STAREOF

run_and_log "Write starship config" true && SUCCESS+=("starship-config")

# ---------- Consolas font attempt ----------
if ! brew tap | grep -q '^homebrew/cask-fonts$'; then
  run_and_log "brew tap homebrew/cask-fonts" brew tap homebrew/cask-fonts || true
fi

if brew search --casks font-consolas >/dev/null 2>&1; then
  run_and_log "Install font-consolas via brew" brew install --cask font-consolas || true
else
  log_warn "Consolas font not found in homebrew/cask-fonts. Marked as WARNING; manual install recommended."
  WARNINGS+=("font-consolas-not-available")
fi

# ---------- xbar plugin (2s refresh) ----------
run_and_log "Create xbar plugins dir" mkdir -p "$PLUGINS_DIR" || true

cat > "$PLUGIN_PATH" <<'PLUGIN_EOF'
#!/usr/bin/env bash
# <xbar.title>Network Speed (Upload/Download)</xbar.title>
# <xbar.version>1.2</xbar.version>
# <xbar.author>Automated installer</xbar.author>
# <xbar.desc>Show download/upload speed in menu bar. Refresh: 2s</xbar.desc>

TMP_DIR="/tmp"
STORAGE_PREFIX="xbar_net_speed"

get_default_iface() {
  iface="$(route get default 2>/dev/null | awk -F: '/interface:/{gsub(/ /,"",$2); print $2; exit}')"
  if [ -n "$iface" ]; then echo "$iface"; return 0; fi
  for f in en0 en1 en2 en3 bridge0 p2p0 awdl0; do
    if ifconfig "$f" >/dev/null 2>&1; then echo "$f"; return 0; fi
  done
  echo ""; return 1
}

read_counters() {
  local iface="$1"
  out=$(netstat -ib 2>/dev/null)
  [ -z "$out" ] && { echo "NA NA"; return 1; }
  line=$(printf "%s\n" "$out" | awk -v ifc="$iface" '$1==ifc {print}' | tail -n1)
  [ -z "$line" ] && { echo "NA NA"; return 1; }
  nums=$(printf "%s\n" "$line" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/) printf "%s ", $i }')
  set -- $nums
  n=$#
  if [ "$n" -ge 2 ]; then
    eval "last=\${$n}"
    eval "prev=\${$((n-1))}"
    echo "$prev $last"; return 0
  fi
  echo "NA NA"; return 1
}

human_rate() {
  local b="$1"
  if [ -z "$b" ] || [ "$b" = "NA" ]; then echo "--"; return; fi
  if [ "$b" -lt 1024 ]; then echo "${b}B/s"; return; fi
  if [ "$b" -lt 1048576 ]; then awk "BEGIN{printf \"%.1fKB/s\", $b/1024}"; return; fi
  awk "BEGIN{printf \"%.2fMB/s\", $b/1048576}"
}

iface="$(get_default_iface)"
[ -z "$iface" ] && { echo "⬇︎ -- ⬆︎ --"; echo "---"; echo "No network interface"; exit 0; }

read -r iby oby <<< "$(read_counters "$iface")"
storage_file="$TMP_DIR/${STORAGE_PREFIX}_${iface}.dat"
now_ts=$(date +%s)

rate_in="NA"; rate_out="NA"

if [ -f "$storage_file" ]; then
  read -r prev_ts prev_iby prev_oby < "$storage_file" || true
  dt=$((now_ts - prev_ts)); [ "$dt" -le 0 ] && dt=1
  if [ "$iby" != "NA" ] && [ -n "$prev_iby" ]; then
    d_in=$((iby - prev_iby)); [ "$d_in" -lt 0 ] && d_in=0
    rate_in=$(awk "BEGIN{printf \"%.1f\", $d_in/$dt}")
  fi
  if [ "$oby" != "NA" ] && [ -n "$prev_oby" ]; then
    d_out=$((oby - prev_oby)); [ "$d_out" -lt 0 ] && d_out=0
    rate_out=$(awk "BEGIN{printf \"%.1f\", $d_out/$dt}")
  fi
fi

printf "%s %s %s\n" "$now_ts" "${iby:-NA}" "${oby:-NA}" > "$storage_file" 2>/dev/null || true

pretty_in="$(human_rate "$rate_in")"
pretty_out="$(human_rate "$rate_out")"

echo "⬇︎ $pretty_in ⬆︎ $pretty_out"
echo "---"
echo "Interface: $iface"
[ "$rate_in" = "NA" ] && echo "Download: --" || echo "Download: $rate_in B/s"
[ "$rate_out" = "NA" ] && echo "Upload: --" || echo "Upload: $rate_out B/s"
echo "---"
echo "Refresh now | refresh=true"
echo "Reset counters | bash='rm' param1='-f' param2='$storage_file' terminal=false"
PLUGIN_EOF

run_and_log "Write xbar plugin" chmod +x "$PLUGIN_PATH" || true

# Add xbar and itsycal to Login Items (if installed)
if brew list --cask xbar >/dev/null 2>&1; then
  run_and_log "Add xbar to Login Items" osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/xbar.app", hidden:false}' || true
  run_and_log "Launch xbar" open -a "xbar" || true
else
  log_warn "xbar not installed; skipping login item setup"
  WARNINGS+=("xbar-not-installed-for-loginitem")
fi

if brew list --cask itsycal >/dev/null 2>&1; then
  run_and_log "Add itsycal to Login Items" osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Itsycal.app", hidden:false}' || true
  run_and_log "Launch itsycal" open -a "Itsycal" || true
else
  log_warn "Itsycal not installed; skipping login item setup"
  WARNINGS+=("itsycal-not-installed-for-loginitem")
fi

# ---------- Patch Ghostty config in Application Support ----------
mkdir -p "$GHOSTTY_AS_APP_SUPPORT_DIR"
TIMESTAMP="$(date +%s)"
if [ -f "$GHOSTTY_CONFIG_PATH" ]; then
  run_and_log "Backup existing Ghostty config" cp "$GHOSTTY_CONFIG_PATH" "$GHOSTTY_CONFIG_PATH.bak.$TIMESTAMP" || true
fi

# helper: replace or append TOML key
replace_or_append_toml() {
  local file="$1"; local key="$2"; local value="$3"
  if [ -f "$file" ] && grep -q "^[[:space:]]*$key[[:space:]]*=" "$file"; then
    sed -E -i.bak "s|^[[:space:]]*($key)[[:space:]]*=.*$|\1 = $value|" "$file" 2>/dev/null || sed -E -i '' "s|^[[:space:]]*($key)[[:space:]]*=.*$|\1 = $value|" "$file"
  else
    printf "%s = %s\n" "$key" "$value" >> "$file"
  fi
}

touch "$GHOSTTY_CONFIG_PATH" 2>>"$LOGFILE" || true

replace_or_append_toml "$GHOSTTY_CONFIG_PATH" "font-family" "\"Consolas\""
replace_or_append_toml "$GHOSTTY_CONFIG_PATH" "font-size" "13"
replace_or_append_toml "$GHOSTTY_CONFIG_PATH" "theme" "\"Abernathy\""
replace_or_append_toml "$GHOSTTY_CONFIG_PATH" "window-inherit-font-size" "false"

if grep -q "font-family" "$GHOSTTY_CONFIG_PATH" 2>/dev/null && grep -q "font-size" "$GHOSTTY_CONFIG_PATH" 2>/dev/null && grep -q "theme" "$GHOSTTY_CONFIG_PATH" 2>/dev/null; then
  log_success "Ghostty config patched at: $GHOSTTY_CONFIG_PATH"
  SUCCESS+=("ghostty-config-patched")
else
  log_fail "Failed to patch Ghostty config (check $GHOSTTY_CONFIG_PATH)"
  FAILURE+=("ghostty-config-patch-failed")
fi

if [[ " ${WARNINGS[*]} " == *"font-consolas-not-available"* ]]; then
  log_warn "Consolas not installed via brew. Manual install recommended: copy Consolas TTF files to ~/Library/Fonts/"
fi

# ---------- Final summary ----------
{
  echo
  echo "========== SUMMARY $(date) =========="
  echo "Successful tasks (${#SUCCESS[@]}):"
  for s in "${SUCCESS[@]}"; do echo "  - $s"; done
  echo
  echo "Warnings (${#WARNINGS[@]}):"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
  echo
  echo "Failed tasks (${#FAILURE[@]}):"
  for f in "${FAILURE[@]}"; do echo "  - $f"; done
  echo
  echo "Ghostty config location: $GHOSTTY_CONFIG_PATH"
  echo "xbar plugin: $PLUGIN_PATH (2s refresh)"
  echo "Starship config: $HOME/.config/starship.toml"
  echo "Log file: $LOGFILE"
} >> "$LOGFILE"

# Print colored summary to terminal
printf "\n${BOLD}===== SUMMARY =====${RESET}\n"
printf "Log file: %s\n\n" "$LOGFILE"

printf "${GREEN}Successful tasks (%d):${RESET}\n" "${#SUCCESS[@]}"
for s in "${SUCCESS[@]}"; do printf "  - %s\n" "$s"; done

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  printf "\n${YELLOW}Warnings (%d):${RESET}\n" "${#WARNINGS[@]}"
  for w in "${WARNINGS[@]}"; do printf "  - %s\n" "$w"; done
fi

if [ "${#FAILURE[@]}" -gt 0 ]; then
  printf "\n${RED}Failed tasks (%d):${RESET}\n" "${#FAILURE[@]}"
  for f in "${FAILURE[@]}"; do printf "  - %s\n" "$f"; done
else
  printf "\n${GREEN}All tasks completed successfully.${RESET}\n"
fi

printf "\nGhostty config written/patched at: %s\n" "$GHOSTTY_CONFIG_PATH"
printf "xbar plugin: %s (2s refresh). First run may display '⬇︎ -- ⬆︎ --' while baseline is collected.\n" "$PLUGIN_PATH"
printf "Starship config: %s\n" "$HOME/.config/starship.toml"

exit 0

