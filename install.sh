#!/usr/bin/env bash
# install.sh
# Sets up the language servers and debuggers for the languages you pick, on Linux or a Mac,
# without sudo. It does not install the languages themselves (Python, Go, Node, compilers).
#
#   ./install.sh               pick from a checklist
#   ./install.sh python go     no checklist; "all" picks every language
#
# The installing is done by Neovim's :InstallTools, so Neovim must read its config from
# this folder. Written for bash 3.2, the version a Mac ships.

names=(python go c js rust) # the language names in init.lua's `tools`
labels=(Python Go 'C/C++' 'JS/TS' Rust)
picks=()
status=0

usage() {
  printf 'Usage: %s [language ...]\n' "$0"
  printf 'Languages: %s, or all. With none, pick from a checklist.\n' "${names[*]}"
}

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

is_name() {
  local name
  for name in "${names[@]}"; do [[ $name == "$1" ]] && return 0; done
  return 1
}

# The checklist. Fills `picks`; returns 1 if you quit.
cur=0
on=()
draw() {
  local i mark pointer
  [[ $1 == again ]] && printf '\033[%dA' "${#names[@]}" # back up over the last drawing
  for i in "${!names[@]}"; do
    mark=' ' && ((on[i])) && mark=x
    pointer=' ' && ((i == cur)) && pointer='>'
    printf '\r\033[2K %s [%s] %s\n' "$pointer" "$mark" "${labels[i]}"
  done
}

checklist() {
  local i key rest n=${#names[@]} all
  for ((i = 0; i < n; i++)); do on[i]=0; done
  printf 'Pick the languages to set up.\n'
  printf 'Up/down: move   Space: tick   a: tick all   Enter: go   q: quit\n\n'
  printf '\033[?25l' # hide the cursor while the list is up
  trap 'printf "\033[?25h"' EXIT
  trap 'exit 130' INT
  draw
  while :; do
    IFS= read -rsn1 key || return 1 # end of input counts as quitting
    case $key in
      $'\033') # arrow keys arrive as ESC [ A and ESC [ B
        IFS= read -rsn2 -t 1 rest
        [[ $rest == '[A' ]] && cur=$(((cur + n - 1) % n))
        [[ $rest == '[B' ]] && cur=$(((cur + 1) % n))
        ;;
      k) cur=$(((cur + n - 1) % n)) ;;
      j) cur=$(((cur + 1) % n)) ;;
      ' ') on[cur]=$((1 - on[cur])) ;;
      a)
        all=0
        for ((i = 0; i < n; i++)); do ((on[i])) || all=1; done
        for ((i = 0; i < n; i++)); do on[i]=$all; done
        ;;
      q) return 1 ;;
      '') break ;; # Enter
    esac
    draw again
  done
  printf '\033[?25h\n'
  for ((i = 0; i < n; i++)); do ((on[i])) && picks+=("${names[i]}"); done
  return 0
}

# What `lang` needs and this machine lacks, as one line; empty when nothing is missing.
missing_for() {
  local lacks=()
  case $1 in
    python)
      if ! have python3; then
        lacks+=(python3)
      else
        # Mason installs the Python tools into a virtual environment.
        local tmp
        tmp=$(mktemp -d) || return
        python3 -m venv "$tmp/venv" >/dev/null 2>&1 || lacks+=("python3's venv module (Debian/Ubuntu: python3-venv)")
        rm -rf "$tmp"
      fi
      ;;
    go) have go || lacks+=(go) ;;
    c)
      have cc || lacks+=('cc (a C compiler)')
      have unzip || lacks+=(unzip)
      have curl || have wget || lacks+=('curl or wget')
      ;;
    js)
      have node || lacks+=(node)
      have npm || lacks+=(npm)
      ;;
    rust)
      have rustup || lacks+=(rustup)
      have unzip || lacks+=(unzip)
      have curl || have wget || lacks+=('curl or wget')
      ;;
  esac
  local item line=''
  for item in "${lacks[@]}"; do line+="${line:+, }$item"; done
  printf '%s' "$line"
}

label_of() {
  local i
  for i in "${!names[@]}"; do [[ ${names[i]} == "$1" ]] && printf '%s' "${labels[i]}"; done
}

# Language names from the command line; with none, the checklist needs a terminal.
if (($# == 0)); then
  [[ -t 0 && -t 1 ]] || { usage >&2; exit 2; }
fi
for arg in "$@"; do
  case $arg in
    -h | --help) usage; exit 0 ;;
    all) picks=("${names[@]}") ;;
    *)
      is_name "$arg" || { printf 'Unknown language: %s\n' "$arg" >&2; usage >&2; exit 2; }
      picks+=("$arg")
      ;;
  esac
done

# Neovim 0.12 or later, reading its config from this folder.
have nvim || die 'nvim not found. Install Neovim 0.12 or later first.'
if [[ $(nvim --version) =~ NVIM\ v0\.([0-9]+) ]] && ((BASH_REMATCH[1] < 12)); then
  die "Neovim 0.12 or later is needed; this is ${BASH_REMATCH[0]#NVIM }."
fi
src=${BASH_SOURCE[0]}
[[ $src == */* ]] || src=./$src
here=$(cd -P "${src%/*}" && pwd)
config=${XDG_CONFIG_HOME:-$HOME/.config}/nvim
if [[ $(cd -P "$config" 2>/dev/null && pwd) != "$here" ]]; then
  die "Neovim reads its config from $config, but this copy is in $here.
Clone it there, or link it: ln -s \"$here\" \"$config\""
fi

if ((${#picks[@]} == 0)); then
  checklist || { printf 'Quit; nothing was changed.\n'; exit 0; }
  ((${#picks[@]} > 0)) || { printf 'Nothing picked; nothing was changed.\n'; exit 0; }
fi

# Skip a language whose prerequisites are missing, and say why.
ready=()
for lang in "${picks[@]}"; do
  lacks=$(missing_for "$lang")
  if [[ -n $lacks ]]; then
    printf 'Skipping %s: %s not found.\n' "$(label_of "$lang")" "$lacks"
    status=1
  else
    ready+=("$lang")
  fi
done
((${#ready[@]} > 0)) || exit "$status"

for lang in "${ready[@]}"; do
  if [[ $lang == rust ]]; then
    rustup component add rust-analyzer || status=1
  fi
done

printf 'Setting up: %s\n' "${ready[*]}"
nvim --headless "+InstallTools! ${ready[*]}" '+cquit 1' || status=1

# Optional extras this script leaves to you.
for lang in "${ready[@]}"; do
  if [[ $lang == python ]]; then
    python3 -c 'import debugpy' 2>/dev/null ||
      printf 'Note: Python debugging (F6) needs debugpy: python3 -m pip install debugpy\n'
    data=${XDG_DATA_HOME:-$HOME/.local/share}/nvim
    { have dot && [[ -d $data/memory-graph ]]; } ||
      printf 'Note: the debugger memory picture needs graphviz and memory_graph; see the README.\n'
  fi
done
have rg || printf 'Note: Space / (search in project) needs ripgrep (rg).\n'

exit "$status"
