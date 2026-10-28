#!/usr/bin/env bash
# stash app installer: makes whatever the user dropped in the Ryoku stash
# launchable. a FreeBSD package (.pkg) goes to `pkg add` via pkexec, and the
# launcher reads the entry the package itself ships; a self-contained tarball
# is extracted under ~/.local and gets a synthesized XDG desktop entry.
# on success the source is dropped from the stash so it doesn't sit there as a
# duplicate (RYOKU_STASH_KEEP=1 keeps it).
#
#   stash-install.sh [file]   (no arg = install every supported file in $STASH)
#
# stdout protocol, read by Singletons/Stash.qml: "@AUTH" right before a polkit
# prompt (the shell steps its deck aside), "OK <name>" per install, and a final
# summary line.
set -u

STASH="${STASH_DIR:-$HOME/Downloads/Stash}"
APPSTORE="$HOME/.local/share/ryoku-apps"
APPDIR="$HOME/.local/share/applications"
ICONDIR="$HOME/.local/share/icons"
KEEP_SOURCE="${RYOKU_STASH_KEEP:-0}"
mkdir -p "$APPSTORE" "$APPDIR" "$ICONDIR"

LAST_NAME=""

slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

cleanup_source() {
  [ "$KEEP_SOURCE" = 1 ] && return 1
  rm -f "$1" 2>/dev/null
  [ ! -e "$1" ]
}

# a FreeBSD package is a tarball whose first members are +COMPACT_MANIFEST and
# +MANIFEST, whatever the file is named.
is_freebsd_pkg() {
  tar -tf "$1" 2>/dev/null | head -n 4 | grep -qE '^\+(COMPACT_)?MANIFEST$'
}

classify() {
  case "$1" in
    *.pkg) printf 'pkg' ;;
    *.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tzst|*.tar.bz2)
      if is_freebsd_pkg "$1"; then printf 'pkg'; else printf 'tarball'; fi ;;
    *) printf 'unknown' ;;
  esac
}

strip_tar_ext() {
  local n="$1" e
  for e in .tar.gz .tgz .tar.xz .txz .tar.zst .tzst .tar.bz2 .tar; do
    case "$n" in *"$e") printf '%s' "${n%"$e"}"; return ;; esac
  done
  printf '%s' "$n"
}

# desktop_get FILE KEY: first value of an unlocalized KEY from [Desktop Entry],
# so Name=/Icon= from Desktop Action groups never leak in.
desktop_get() {
  awk -v k="$2" '
    /^\[/ { inentry = ($0 == "[Desktop Entry]"); next }
    inentry {
      eq = index($0, "=")
      if (eq > 0) {
        key = substr($0, 1, eq - 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        if (key == k) { print substr($0, eq + 1); exit }
      }
    }
  ' "$1" 2>/dev/null
}

# exec_field PATH: double-quote the program token if it has whitespace, per the
# desktop entry Exec syntax.
exec_field() {
  case "$1" in
    *[[:space:]]*) printf '"%s"' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

# find_icon_file ROOT ICONVALUE: prefer a scalable SVG, then the highest-res
# themed PNG, then anything with the right name near the top of the tree.
find_icon_file() {
  local root="$1" icon="$2" bn found=""
  [ -n "$icon" ] || return
  [ -f "$icon" ] && { printf '%s' "$icon"; return; }
  bn=$(basename "$icon"); bn="${bn%.*}"
  found=$(find "$root" -type f -ipath '*/icons/*' -iname "$bn.svg" 2>/dev/null | head -n1)
  [ -z "$found" ] && found=$(find "$root" -type f -ipath '*/icons/*' -iname "$bn.png" 2>/dev/null \
    | awk '{ n=$0; sz=0; if (match(n, /\/[0-9]+x[0-9]+\//)) { s=substr(n, RSTART+1, RLENGTH-2); split(s, a, "x"); sz=a[1] } print sz"\t"n }' \
    | sort -rn | head -n1 | cut -f2-)
  [ -z "$found" ] && found=$(find "$root" -maxdepth 4 -type f \( -iname "$bn.png" -o -iname "$bn.svg" -o -iname "$bn.xpm" \) 2>/dev/null | head -n1)
  printf '%s' "$found"
}

install_icon() {
  local src="$1" appname="$2" ext
  [ -f "$src" ] || return
  case "$src" in *.svg) ext=svg ;; *.xpm) ext=xpm ;; *) ext=png ;; esac
  cp -f "$src" "$ICONDIR/$appname.$ext" 2>/dev/null && printf '%s' "$ICONDIR/$appname.$ext"
}

# write_desktop OUT NAME EXEC ICON COMMENT CATEGORIES
write_desktop() {
  local cat="${6:-Utility;}"
  case "$cat" in *\;) ;; *) cat="$cat;" ;; esac
  {
    printf '[Desktop Entry]\nType=Application\nVersion=1.0\n'
    printf 'Name=%s\n' "$2"
    [ -n "$5" ] && printf 'Comment=%s\n' "$5"
    printf 'Exec=%s\nIcon=%s\nTerminal=false\nCategories=%s\nX-Ryoku-Stash=true\n' "$3" "${4:-$2}" "$cat"
  } >"$1"
}

# pick_executable ROOT WANT: an executable named WANT, else the sole executable
# in the tree, else "" (ambiguous).
pick_executable() {
  local list match
  list=$(find "$1" -type f -perm -u+x ! -iname '*.desktop' 2>/dev/null)
  [ -n "$list" ] || return
  match=$(printf '%s\n' "$list" | while IFS= read -r f; do
    [ "$(basename "$f")" = "$2" ] && { printf '%s' "$f"; break; }
  done)
  [ -n "$match" ] && { printf '%s' "$match"; return; }
  [ "$(printf '%s\n' "$list" | wc -l)" -eq 1 ] && printf '%s' "$list"
}

# install_tar_desktop ROOT DESKTOP FALLBACK: install a .desktop found in the
# extracted tree, rewriting Exec to the bundled binary's absolute path.
install_tar_desktop() {
  local root="$1" ed="$2" fallback="$3" appname nm cm cat icv oexec tok rest="" abs="" execval iconfile iconinstalled=""
  appname=$(slug "$(basename "$ed" .desktop)")
  [ -n "$appname" ] || appname="$fallback"
  nm=$(desktop_get "$ed" Name)
  cm=$(desktop_get "$ed" Comment)
  cat=$(desktop_get "$ed" Categories)
  icv=$(desktop_get "$ed" Icon)
  oexec=$(desktop_get "$ed" Exec)
  if [ -n "$oexec" ]; then
    tok=${oexec%% *}
    case "$oexec" in *" "*) rest=${oexec#* } ;; esac
    case "$tok" in /*) [ -f "$root$tok" ] && abs="$root$tok" ;; esac
    [ -z "$abs" ] && abs=$(find "$root" -type f -name "$(basename "$tok")" 2>/dev/null | head -n1)
    [ -z "$abs" ] && abs="$tok"
  else
    abs=$(pick_executable "$root" "$fallback")
  fi
  [ -f "$abs" ] && chmod +x "$abs" 2>/dev/null
  execval="$(exec_field "$abs")"
  [ -n "$rest" ] && execval="$execval $rest"
  iconfile=$(find_icon_file "$root" "$icv")
  [ -n "$iconfile" ] && iconinstalled=$(install_icon "$iconfile" "$appname")
  write_desktop "$APPDIR/$appname.desktop" "${nm:-$fallback}" "$execval" "${iconinstalled:-${icv:-$appname}}" "$cm" "$cat"
  LAST_NAME="$appname"
}

# install_tarball SRC: extract into a fresh app-store dir, then a shipped
# .desktop (Exec rewritten) or a lone executable becomes the launcher entry.
# best-effort: an app that hardcodes /usr/local still needs its real package.
install_tarball() {
  local rawname name dst ed exe
  rawname=$(strip_tar_ext "$(basename "$1")")
  name=$(slug "$rawname"); [ -n "$name" ] || name="app"
  dst="$APPSTORE/$name"
  rm -rf "$dst"; mkdir -p "$dst"
  tar -xf "$1" -C "$dst" >/dev/null 2>&1 || return 1
  ed=$(find "$dst" -type f -name '*.desktop' 2>/dev/null | head -n1)
  if [ -n "$ed" ]; then
    install_tar_desktop "$dst" "$ed" "$rawname"
    return 0
  fi
  exe=$(pick_executable "$dst" "$rawname")
  [ -n "$exe" ] || return 1
  chmod +x "$exe" 2>/dev/null
  write_desktop "$APPDIR/$name.desktop" "$rawname" "$(exec_field "$exe")" "$name" "" "Utility;"
  LAST_NAME="$name"
}

# install_pkg SRC: `pkg add` through pkexec, since the stash runs with no tty.
# pkg resolves the package's dependencies from the configured repositories.
install_pkg() {
  command -v pkexec >/dev/null 2>&1 || return 1
  printf '@AUTH\n'
  pkexec pkg add "$1" >/dev/null 2>&1 || return 1
  LAST_NAME=$(pkg query -F "$1" '%n' 2>/dev/null || slug "$(basename "$1" .pkg)")
}

# install_one FILE: 0 ok, 1 fail, 2 unsupported.
install_one() {
  LAST_NAME=""
  [ -f "$1" ] || return 1
  case "$(classify "$1")" in
    pkg) install_pkg "$1" || return 1 ;;
    tarball) install_tarball "$1" || return 1 ;;
    *) return 2 ;;
  esac
}

single=0
targets=()
if [ "$#" -ge 1 ]; then
  single=1
  targets=("$1")
else
  shopt -s nullglob
  for f in "$STASH"/*; do
    [ -f "$f" ] || continue
    case "$(classify "$f")" in pkg|tarball) targets+=("$f") ;; esac
  done
  shopt -u nullglob
fi

NAMES=()
attempted=0
cleaned=0
for t in "${targets[@]}"; do
  install_one "$t"; rc=$?
  if [ "$rc" -eq 0 ]; then
    attempted=$((attempted + 1))
    NAMES+=("$LAST_NAME")
    cleanup_source "$t" && cleaned=$((cleaned + 1))
    echo "OK $LAST_NAME"
  elif [ "$rc" -eq 2 ]; then
    # unsupported: an error only when the user named the file explicitly.
    [ "$single" -eq 1 ] && attempted=$((attempted + 1))
  else
    attempted=$((attempted + 1))
  fi
done

if [ "${#NAMES[@]}" -gt 0 ]; then
  update-desktop-database "$APPDIR" 2>/dev/null || true
  names_str=$(printf '%s, ' "${NAMES[@]}"); names_str=${names_str%, }
  msg="Installed $names_str"
  [ "$cleaned" -gt 0 ] && msg="$msg, cleared from stash"
  notify-send "Stash" "$msg" -i emblem-ok-symbolic
  echo "$msg"
  exit 0
fi

if [ "$attempted" -gt 0 ]; then
  notify-send "Stash" "Install failed" -i dialog-error
  echo "Install failed" >&2
  exit 1
fi

echo "Nothing to install"
exit 0
