#!/usr/bin/env bash
# install.sh: install Sova so you can run `sova FILE` from any folder.
#
#   curl -fsSL https://raw.githubusercontent.com/soumil-voona/sova/main/install.sh | bash
#
# From a clone, run `./install.sh` to install that copy instead of
# downloading. To remove Sova, run the same command with --uninstall:
#
#   curl -fsSL https://raw.githubusercontent.com/soumil-voona/sova/main/install.sh | bash -s -- --uninstall
#
# Settings (environment variables):
#   SOVA_HOME     where the code goes      (default ~/.local/share/sova)
#   SOVA_BIN_DIR  where the `sova` link goes (default ~/.local/bin)
#   SOVA_REF      branch or tag to download (default main)
#   SOVA_URL      tarball to download instead (for mirrors and testing)

set -euo pipefail

REPO="soumil-voona/sova"
SOVA_HOME="${SOVA_HOME:-$HOME/.local/share/sova}"
SOVA_BIN_DIR="${SOVA_BIN_DIR:-$HOME/.local/bin}"
SOVA_REF="${SOVA_REF:-main}"

say()  { printf '%s\n' "$*"; }
fail() { printf 'sova install: %s\n' "$*" >&2; exit 1; }

uninstall() {
    # Only remove the link if it is ours, not one made by hand to a clone.
    if [[ -L "$SOVA_BIN_DIR/sova" && "$(readlink "$SOVA_BIN_DIR/sova")" == "$SOVA_HOME/sova" ]]; then
        rm -f "$SOVA_BIN_DIR/sova"
        say "Removed $SOVA_BIN_DIR/sova"
    elif [[ -L "$SOVA_BIN_DIR/sova" ]]; then
        say "Left $SOVA_BIN_DIR/sova alone: it points to $(readlink "$SOVA_BIN_DIR/sova"), not this install"
    fi
    if [[ -f "$SOVA_HOME/sova" && -d "$SOVA_HOME/src" ]]; then
        rm -rf "$SOVA_HOME"
        say "Removed $SOVA_HOME"
    fi
    say "Sova is uninstalled."
}

if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
    exit 0
fi

# Refuse to install over a folder that isn't a Sova install.
if [[ -e "$SOVA_HOME" && ! ( -f "$SOVA_HOME/sova" && -d "$SOVA_HOME/src" ) ]]; then
    fail "$SOVA_HOME exists and isn't a Sova install; set SOVA_HOME to another folder"
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/sova-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

# Use the clone this script sits in, if there is one; otherwise download.
script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

mkdir -p "$staging/sova"
if [[ -n "$script_dir" && -f "$script_dir/sova" && -d "$script_dir/src" ]]; then
    say "Installing Sova from $script_dir"
    cp -R "$script_dir/sova" "$script_dir/src" "$script_dir/examples" \
          "$script_dir/exercises" "$script_dir/install.sh" "$staging/sova/"
else
    url="https://github.com/$REPO/archive/refs/heads/$SOVA_REF.tar.gz"
    [[ "$SOVA_REF" == v[0-9]* ]] && url="https://github.com/$REPO/archive/refs/tags/$SOVA_REF.tar.gz"
    url="${SOVA_URL:-$url}"
    say "Downloading Sova ($SOVA_REF)..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$staging/sova.tar.gz" || fail "download failed: $url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$staging/sova.tar.gz" "$url" || fail "download failed: $url"
    else
        fail "need curl or wget to download Sova"
    fi
    mkdir -p "$staging/extract"
    tar -xzf "$staging/sova.tar.gz" -C "$staging/extract"
    top="$(find "$staging/extract" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -f "$top/sova" && -d "$top/src" ]] || fail "the download doesn't look like Sova"
    cp -R "$top/sova" "$top/src" "$top/examples" "$top/exercises" "$staging/sova/"
    [[ -f "$top/install.sh" ]] && cp "$top/install.sh" "$staging/sova/"
fi
chmod +x "$staging/sova/sova"

# Swap the new copy in.
mkdir -p "$(dirname "$SOVA_HOME")" "$SOVA_BIN_DIR"
rm -rf "$SOVA_HOME"
mv "$staging/sova" "$SOVA_HOME"
ln -sf "$SOVA_HOME/sova" "$SOVA_BIN_DIR/sova"

"$SOVA_BIN_DIR/sova" --brief "$SOVA_HOME/examples/family.sova" >/dev/null 2>&1 \
    || fail "installed, but a test run failed; try: $SOVA_BIN_DIR/sova $SOVA_HOME/examples/family.sova"

say "Installed Sova to $SOVA_HOME"
say "Linked $SOVA_BIN_DIR/sova"

case ":$PATH:" in
    *":$SOVA_BIN_DIR:"*)
        say ""
        say "Try it:  sova $SOVA_HOME/examples/family.sova"
        ;;
    *)
        case "${SHELL:-}" in
            */zsh)  rc="$HOME/.zshrc" ;;
            */bash) rc="$HOME/.bashrc" ;;
            *)      rc="your shell's startup file" ;;
        esac
        say ""
        say "$SOVA_BIN_DIR is not on your PATH yet. Add this line to $rc:"
        say ""
        say "    export PATH=\"$SOVA_BIN_DIR:\$PATH\""
        say ""
        say "then open a new terminal and run:  sova $SOVA_HOME/examples/family.sova"
        ;;
esac
