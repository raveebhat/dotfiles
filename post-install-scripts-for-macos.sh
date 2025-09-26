#!/usr/bin/env bash
set -euo pipefail

# post-install-mac-final.sh
# - Writes only our logs to $LOGFILE (no command stdout/stderr capture)
# - Uses run_and_log helper (runs commands with output suppressed)
# - Measures per-task elapsed time and prints a timing summary
# - Installs specified apps, sets default browser to Brave, installs google-chrome, installs outline-manager
# - Adds xbar & itsycal to Login Items and launches
# - Patches Ghostty config in ~/Library/Application Support/ghostty/config
# - Places xbar plugin net-speed.2s.sh in plugins folder
# - Opens Outline Client App Store page for manual installation
# Usage:
#   chmod +x post-install-mac-final.sh
#   ./post-install-mac-final.sh

LOGFILE="$HOME/post_install_report.txt"

# Print where we will write output before prompting
echo
echo "This script will write only our status logs (no command stdout/stderr) to:"
echo "  $LOGFILE"
echo "Commands will run with their stdout/stderr suppressed to keep installs clean and fast."
echo

# ANSI colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
BOLD="\033[1m"
RESET="\033[0m"

# initialize log file header
printf "Post-install run started at: %s\n\n" "$(date '+%F %T')" >> "$LOGFILE"

# arrays for results and timings
SUCCESS=()
FAILURE=()
WARNINGS=()
TASK_NAMES=()
TASK_SECS=()

# logging helpers (these write only our messages to logfile)
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

# separator helper (visible in terminal and appended to logfile)
print_sep() {
  local title="$1"
  local sep="================================================================="
  printf "\n${BOLD}${sep}\n  %s\n${sep}${RESET}\n" "$title"
  printf "\n%s\n  %s\n%s\n" "$sep" "$title" "$sep" >> "$LOGFILE"
}

# ---------- run_and_log helper (your exact structure, but measures time and suppresses command output) ----------
run_and_log() {
  # args: <task-name> <command...>
  local task="$1"; shift
  printf "\n${BOLD}>>> START TASK: %s${RESET}\n" "$task"
  printf "[%s] START: %s\n" "$(date '+%F %T')" "$task" >> "$LOGFILE"

  # timing
  local start_ts end_ts elapsed
  start_ts=$(date +%s)

  # run command with stdout/stderr suppressed (so command output DOES NOT go to logfile)
  if "$@" >/dev/null 2>&1; then
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    log_success "TASK SUCCESS: $task"
    SUCCESS+=("$task")
    TASK_NAMES+=("$task")
    TASK_SECS+=("$elapsed")
    printf "[%s] END: %s (success, %ds)\n" "$(date '+%F %T')" "$task" "$elapsed" >> "$LOGFILE"
    return 0
  else
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    log_fail "TASK FAILED: $task (see terminal for hint)."
    FAILURE+=("$task")
    TASK_NAMES+=("$task")
    TASK_SECS+=("$elapsed")
    printf "[%s] END: %s (failed, %ds)\n" "$(date '+%F %T')" "$task" "$elapsed" >> "$LOGFILE"
    return 1
  fi
}

# prompt before proceeding
echo "Log file (only our logs) will be: $LOGFILE"
read -r -p "Proceed with installations and config changes? [Y/n]: " PROCEED
case "$PROCEED" in
  "" | [Yy]* ) log_info "User accepted, continuing..." ;;
  * ) log_info "Aborted by user."; exit 0 ;;
esac

# ---------- Config: packages & paths ----------
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
  outline-manager
  google-chrome
)
FORMULAE=(
  starship
  bash
  duti
)

PLUGINS_DIR="$HOME/Library/Application Support/xbar/plugins"
PLUGIN_NAME="net-speed.2s.sh"
PLUGIN_PATH="$PLUGINS_DIR/$PLUGIN_NAME"

GHOSTTY_AS_APP_SUPPORT_DIR="$HOME/Library/Application Support/ghostty"
GHOSTTY_CONFIG_PATH="$GHOSTTY_AS_APP_SUPPORT_DIR/config"

# ---------- Begin tasks ----------

# 1) Install Homebrew (if missing)
if ! command -v brew >/dev/null 2>&1; then
  print_sep "INSTALL: Homebrew"
  run_and_log "Install Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
else
  print_sep "SKIP: Homebrew already present"
  log_info "Homebrew already present"
  SUCCESS+=("homebrew:present")
fi

# 2) Update brew
print_sep "RUN: brew update"
run_and_log "brew update" brew update || true

# 3) Install formulae
for f in "${FORMULAE[@]}"; do
  if brew list "$f" >/dev/null 2>&1; then
    print_sep "SKIP: formula $f already installed"
    log_info "$f already installed"
    SUCCESS+=("formula:$f")
  else
    print_sep "INSTALL: formula $f"
    run_and_log "brew install $f" brew install "$f" || true
  fi
done

# 4) Install casks
for c in "${CASKS[@]}"; do
  if brew list --cask "$c" >/dev/null 2>&1; then
    print_sep "SKIP: cask $c already installed"
    log_info "cask $c already installed"
    SUCCESS+=("cask:$c")
  else
    print_sep "INSTALL: cask $c"
    run_and_log "brew install --cask $c" brew install --cask "$c" || true
  fi
done

# 5) Add Homebrew bash to /etc/shells and set as default
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /usr/local)"
BREW_BASH="$BREW_PREFIX/bin/bash"

if [ -x "$BREW_BASH" ]; then
  if ! grep -qF "$BREW_BASH" /etc/shells 2>/dev/null; then
    print_sep "Add $BREW_BASH to /etc/shells"
    run_and_log "Add brew bash to /etc/shells" sudo sh -c "echo $BREW_BASH >> /etc/shells"
  else
    print_sep "SKIP: $BREW_BASH already in /etc/shells"
    log_info "$BREW_BASH already listed in /etc/shells"
    SUCCESS+=("shells-contains-brew-bash")
  fi

  CUR_SHELL=$(dscl . -read ~/ UserShell 2>/dev/null | awk '{print $2}' || echo "$SHELL")
  if [ "$CUR_SHELL" != "$BREW_BASH" ]; then
    print_sep "Change default shell to Homebrew bash"
    run_and_log "Change default shell" chsh -s "$BREW_BASH" || true
  else
    print_sep "SKIP: default shell already $BREW_BASH"
    log_info "Default shell already $BREW_BASH"
    SUCCESS+=("chsh:already")
  fi
else
  print_sep "ERROR: Homebrew bash not found"
  log_fail "Homebrew bash not found at $BREW_BASH"
  FAILURE+=("brew-bash-not-found")
fi

# 6) Ensure starship init lines in bash profile/rc
BASH_PROFILE="$HOME/.bash_profile"
BASH_RC="$HOME/.bashrc"
print_sep "Configure starship init in shell profiles"
if ! grep -q "starship init bash" "$BASH_PROFILE" 2>/dev/null; then
  run_and_log "Append starship init to $BASH_PROFILE" bash -lc "echo 'eval \"\$(starship init bash)\"' >> '$BASH_PROFILE'"
else
  log_info "starship init already in $BASH_PROFILE"
  SUCCESS+=("starship-init-exists:$BASH_PROFILE")
fi
if [ -f "$BASH_RC" ] && ! grep -q "starship init bash" "$BASH_RC" 2>/dev/null; then
  run_and_log "Append starship init to $BASH_RC" bash -lc "echo 'eval \"\$(starship init bash)\"' >> '$BASH_RC'"
else
  log_info "starship init already in $BASH_RC or file missing"
fi

# 7) Write starship config
print_sep "Write starship config (~/.config/starship.toml)"
run_and_log "Write starship config" bash -lc "mkdir -p \"\$(dirname \$HOME/.config/starship.toml)\" && cat > \$HOME/.config/starship.toml <<'STAREOF'
# Starship config installed by post-install script
add_newline = false
format = \"$directory$git_branch$character\"

[directory]
truncation_length = 3

[git_branch]
symbol = \"🌱 \"
style = \"yellow\"

[character]
success_symbol = \"[→](bold green)\"
error_symbol = \"[←](bold red)\"
STAREOF
"

# 8) Attempt to install Consolas font via homebrew/cask-fonts
print_sep "Attempt Consolas font (homebrew/cask-fonts)"
if ! brew tap | grep -q '^homebrew/cask-fonts$'; then
  run_and_log "Tap homebrew/cask-fonts" brew tap homebrew/cask-fonts || true
fi
if brew search --casks font-consolas >/dev/null 2>&1; then
  run_and_log "Install font-consolas" brew install --cask font-consolas || true
else
  log_warn "Consolas not found via homebrew/cask-fonts. Marked as warning."
  WARNINGS+=("font-consolas-not-available")
fi

# 9) Create xbar plugins folder and write net-speed.2s.sh plugin
print_sep "Install xbar plugin (net-speed.2s.sh)"
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

run_and_log "Make xbar plugin executable" chmod +x "$PLUGIN_PATH" || true

# 10) Add xbar & itsycal to Login Items and launch (if installed)
print_sep "Add xbar & itsycal to Login Items"
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
  log_warn "itsycal not installed; skipping login item setup"
  WARNINGS+=("itsycal-not-installed-for-loginitem")
fi

# 11) Set Brave as default browser using duti
print_sep "Set default browser to Brave (http/https) using duti"
if command -v duti >/dev/null 2>&1; then
  BRAVE_BUNDLE="com.brave.Browser"
  run_and_log "Set http handler to Brave" duti -s "$BRAVE_BUNDLE" http || true
  run_and_log "Set https handler to Brave" duti -s "$BRAVE_BUNDLE" https || true
  SUCCESS+=("default-browser-set:brave")
else
  log_warn "duti not installed; cannot set default browser automatically"
  WARNINGS+=("duti-missing-default-browser-not-set")
fi

# 12) Open Outline Client App Store page for manual install
print_sep "Open Outline Client App Store page (install manually)"
run_and_log "Open Outline Client App Store" open "https://apps.apple.com/us/app/outline-app/id1356178125" || true
log_info "Opened Outline Client App Store page in default browser. Please install manually."

# 13) Patch Ghostty config in Application Support
print_sep "Patch Ghostty config (Application Support)"
run_and_log "Ensure Ghostty App Support dir" mkdir -p "$GHOSTTY_AS_APP_SUPPORT_DIR" || true

TIMESTAMP="$(date +%s)"
if [ -f "$GHOSTTY_CONFIG_PATH" ]; then
  run_and_log "Backup existing Ghostty config" cp "$GHOSTTY_CONFIG_PATH" "$GHOSTTY_CONFIG_PATH.bak.$TIMESTAMP" || true
fi

# helper to replace or append TOML key (in-place)
replace_or_append_toml() {
  local file="$1"; local key="$2"; local value="$3"
  if [ -f "$file" ] && grep -q "^[[:space:]]*$key[[:space:]]*=" "$file"; then
    # macOS sed: -i '' or fallback to -i.bak; try portable approach
    sed -E -i.bak "s|^[[:space:]]*($key)[[:space:]]*=.*$|\1 = $value|" "$file" 2>/dev/null || sed -E -i '' "s|^[[:space:]]*($key)[[:space:]]*=.*$|\1 = $value|" "$file"
  else
    printf "%s = %s\n" "$key" "$value" >> "$file"
  fi
}

run_and_log "Touch Ghostty config file" touch "$GHOSTTY_CONFIG_PATH" || true

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

if [[ " ${WARNINGS[*]:-} " == *"font-consolas-not-available"* ]]; then
  log_warn "Consolas not installed via brew. Manual install recommended: copy Consolas TTF files to ~/Library/Fonts/"
fi

# ---------- Timing summary helpers ----------
format_time() {
  local secs=$1
  if [ "$secs" -ge 60 ]; then
    local mins=$((secs/60))
    local rem=$((secs%60))
    printf "%d:%02d" "$mins" "$rem"
  else
    printf "%ds" "$secs"
  fi
}

# ---------- Final summary & timing output ----------
print_sep "SUMMARY"
printf "Log file (our logs only): %s\n\n" "$LOGFILE"

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
  printf "\n${GREEN}No failed tasks recorded.${RESET}\n"
fi

# Timing summary
print_sep "TIMING SUMMARY"
total=0
for i in "${!TASK_NAMES[@]}"; do
  name="${TASK_NAMES[$i]}"
  secs="${TASK_SECS[$i]}"
  total=$((total + secs))
  human=$(format_time "$secs")
  printf "%-60s %8s  (%ds)\n" "$name" "$human" "$secs"
  printf "%-60s %8s  (%ds)\n" "$name" "$human" "$secs" >> "$LOGFILE"
done
total_human=$(format_time "$total")
printf "\n%-60s %8s  (%ds)\n" "TOTAL" "$total_human" "$total"
printf "\n%-60s %8s  (%ds)\n" "TOTAL" "$total_human" "$total" >> "$LOGFILE"

# final bookkeeping to logfile
{
  echo
  echo "Run finished at: $(date '+%F %T')"
  echo "Successful tasks: ${#SUCCESS[@]}"
  echo "Warnings: ${#WARNINGS[@]}"
  echo "Failed tasks: ${#FAILURE[@]}"
  echo "Timing total (s): $total"
} >> "$LOGFILE"

echo
echo "Done. Check $LOGFILE for the concise run log (only our logs)."
echo "If you want command outputs captured for debugging, I can modify the script to save each command's stdout/stderr to per-task files."

exit 0

