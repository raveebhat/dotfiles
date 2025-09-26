#!/usr/bin/env bash
set -euo pipefail

# install-xbar-net.sh
# Installs xbar (via Homebrew), places a network-speed xbar plugin in the plugins dir,
# makes it executable, adds xbar to Login Items, and launches xbar.
#
# Add to your dotfiles and run on a fresh mac to auto-provision xbar + plugin.

PLUGINS_DIR="$HOME/Library/Application Support/xbar/plugins"
PLUGIN_NAME="net-speed.2s.sh"
PLUGIN_PATH="$PLUGINS_DIR/$PLUGIN_NAME"
TMP_PREFIX="xbar_net_speed"

# --- 1) Ensure Homebrew is installed (non-interactive minimal)
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Installing Homebrew (requires /bin/bash and some Xcode tools)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Ensure brew in PATH for this script (for both Apple Silicon and Intel)
  if [ -d /opt/homebrew/bin ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)" || true
  fi
  if [ -d /usr/local/bin ]; then
    eval "$(/usr/local/bin/brew shellenv)" || true
  fi
else
  echo "Homebrew found."
fi

# --- 2) Install xbar via Homebrew Cask if not present
if ! brew list --cask xbar >/dev/null 2>&1; then
  echo "Installing xbar..."
  brew install --cask xbar
else
  echo "xbar already installed (brew cask)."
fi

# --- 3) Create plugins folder
mkdir -p "$PLUGINS_DIR"
echo "Using xbar plugins dir: $PLUGINS_DIR"

# --- 4) Write plugin
cat > "$PLUGIN_PATH" <<'EOF'
#!/usr/bin/env bash
# <xbar.title>Network Speed (Upload/Download)</xbar.title>
# <xbar.version>1.1</xbar.version>
# <xbar.author>Automated installer</xbar.author>
# <xbar.desc>Show download/upload speed in menu bar. Minimal single-purpose plugin.</xbar.desc>
# <xbar.image>https://example.com/icon.png</xbar.image>
# <xbar.dependencies>sh,awk,netstat,bc</xbar.dependencies>

# NOTES:
# - Filename determines refresh interval (this file uses 10s).
# - Stores previous counters at /tmp/xbar_net_speed_<iface>.dat
# - First run will show -- for rates (baseline saved). Subsequent runs show actual rates.

TMP_DIR="/tmp"
STORAGE_PREFIX="xbar_net_speed"

# get default interface (route get default works on macOS)
get_default_iface() {
  iface="$(route get default 2>/dev/null | awk -F: '/interface:/{gsub(/ /,"",$2); print $2; exit}')"
  if [ -n "$iface" ]; then
    echo "$iface"
    return 0
  fi
  # fallback common names
  for f in en0 en1 en2 en3 en4 bridge0 p2p0 awdl0; do
    if ifconfig "$f" >/dev/null 2>&1; then
      echo "$f"
      return 0
    fi
  done
  echo ""
  return 1
}

# read counters for iface using netstat -ib and pick last matching line's integer fields
read_counters() {
  local iface="$1"
  # produce two numbers: ibytes obytes
  # netstat -ib output varies, but usually integer rx/tx bytes are somewhere near the end.
  # We find the last line that starts with iface and then extract the last two numeric tokens.
  out=$(netstat -ib 2>/dev/null)
  if [ -z "$out" ]; then
    echo "NA NA"
    return 1
  fi

  # find all lines beginning with iface (exact match)
  lines=$(printf "%s\n" "$out" | awk -v ifc="$iface" '$1 == ifc {print}')
  if [ -z "$lines" ]; then
    # try prefix match (sometimes iface0 vs iface)
    lines=$(printf "%s\n" "$out" | awk -v ifc="$iface" 'index($1,ifc)==1 {print}')
  fi
  if [ -z "$lines" ]; then
    echo "NA NA"
    return 1
  fi

  # take the last matching line
  line=$(printf "%s\n" "$lines" | tail -n1)

  # extract numeric tokens from the line, take last two as obytes and ibytes guess
  nums=$(printf "%s\n" "$line" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/) printf "%s ", $i }')
  # split into array
  set -- $nums
  # if we have at least two numeric fields, pick last two
  n=$#
  if [ "$n" -ge 2 ]; then
    # last token -> candidate Obytes, second last -> Ibytes (but netstat ordering may vary)
    eval "last=\${$n}"
    eval "prev=\${$((n-1))}"
    # print Ibytes Obytes (as our plugin expects)
    echo "$prev $last"
    return 0
  fi

  # fallback: try predefined column positions (may work on most macs)
  # often columns: ... Ibytes ... Obytes -> try fields 7 and 10
  iby=$(printf "%s\n" "$line" | awk '{print $(NF-3)}' 2>/dev/null || true)
  oby=$(printf "%s\n" "$line" | awk '{print $(NF-1)}' 2>/dev/null || true)
  if [ -n "$iby" ] && [ -n "$oby" ]; then
    echo "$iby $oby"
    return 0
  fi

  echo "NA NA"
  return 1
}

human_rate() {
  # input bytes_per_s (float), output like "1.2 MB/s" but compact
  local b="$1"
  if [ -z "$b" ] || [ "$b" = "NA" ]; then
    echo "--"
    return
  fi
  # ensure bc is available for decimal maths; if not, use integer
  if command -v bc >/dev/null 2>&1; then
    if awk "BEGIN {exit !($b < 1024)}"; then
      # bytes
      echo "${b}B/s"
      return
    fi
    if awk "BEGIN {exit !($b < 1048576)}"; then
      kb=$(awk "BEGIN {printf \"%.1f\", $b/1024}")
      echo "${kb}KB/s"
      return
    fi
    mb=$(awk "BEGIN {printf \"%.2f\", $b/1048576}")
    echo "${mb}MB/s"
  else
    # fallback integer KB
    if [ "$b" -lt 1024 ]; then
      echo "${b}B/s"
    elif [ "$b" -lt 1048576 ]; then
      kb=$((b/1024))
      echo "${kb}KB/s"
    else
      mb=$((b/1048576))
      echo "${mb}MB/s"
    fi
  fi
}

# main
iface="$(get_default_iface)"
if [ -z "$iface" ]; then
  echo "⬇︎ -- ⬆︎ --"
  echo "---"
  echo "No network interface"
  exit 0
fi

read -r iby obe <<< "$(read_counters "$iface")" || true

storage_file="$TMP_DIR/${STORAGE_PREFIX}_${iface}.dat"

now_ts=$(date +%s)

rate_in="NA"
rate_out="NA"

if [ -f "$storage_file" ]; then
  read -r prev_ts prev_iby prev_oby < "$storage_file" || true
  if [ -n "$prev_ts" ] && [ -n "$prev_iby" ] && [ -n "$prev_oby" ]; then
    dt=$((now_ts - prev_ts))
    if [ "$dt" -le 0 ]; then dt=1; fi

    # protect against NA
    if [ "$iby" != "NA" ] && [ "$prev_iby" != "NA" ]; then
      d_in=$(( iby - prev_iby ))
      if [ "$d_in" -lt 0 ]; then d_in=0; fi
      # compute float division with awk
      rate_in=$(awk "BEGIN{printf \"%.1f\", $d_in / $dt}")
    fi
    if [ "$obe" != "NA" ] && [ "$prev_oby" != "NA" ]; then
      d_out=$(( obe - prev_oby ))
      if [ "$d_out" -lt 0 ]; then d_out=0; fi
      rate_out=$(awk "BEGIN{printf \"%.1f\", $d_out / $dt}")
    fi
  fi
fi

# save current counters for next run
printf "%s %s %s\n" "$now_ts" "${iby:-NA}" "${obe:-NA}" > "$storage_file" 2>/dev/null || true

# pretty output
pretty_in="$(human_rate "$rate_in")"
pretty_out="$(human_rate "$rate_out")"

echo "⬇︎ $pretty_in ⬆︎ $pretty_out"
echo "---"
echo "Interface: $iface"
if [ "$rate_in" = "NA" ]; then
  echo "Download: --"
else
  echo "Download: $rate_in B/s (raw)"
fi
if [ "$rate_out" = "NA" ]; then
  echo "Upload: --"
else
  echo "Upload: $rate_out B/s (raw)"
fi
echo "---"
echo "Refresh now | refresh=true"
# Reset action - remove storage file
echo "Reset counters (clear cache) | bash='rm' param1='-f' param2='$storage_file' terminal=false"
EOF

# --- 5) Ensure plugin is executable
chmod +x "$PLUGIN_PATH"
echo "Wrote plugin to: $PLUGIN_PATH (executable)"

# --- 6) Open xbar (and set Login Item via AppleScript)
# Add xbar to Login Items so it starts at login.
echo "Adding xbar to Login Items (may prompt for accessibility permissions)."
osascript <<APPLESCRIPT
tell application "System Events"
    -- Check if xbar is already a login item
    set appPath to POSIX file "/Applications/xbar.app" as alias
    set already to false
    repeat with li in login items
        try
            if (path of li as text) = (appPath as text) then
                set already to true
                exit repeat
            end if
        end try
    end repeat
    if not already then
        make login item at end with properties {path:(appPath as text), hidden:false}
    end if
end tell
APPLESCRIPT

# Launch xbar now (this will show menu bar item)
if ! pgrep -x "xbar" >/dev/null 2>&1; then
  echo "Launching xbar..."
  open -a "xbar"
else
  echo "xbar already running."
  # ask xbar to refresh plugins (xbar supports refresh via AppleScript only in newer versions; fallback to reopen)
  open -a "xbar"
fi

echo "Done. If you don't immediately see upload/download in the menu bar, wait ~10 seconds (first run saves baseline)."
echo "Plugin path: $PLUGIN_PATH"

