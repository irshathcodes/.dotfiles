#!/usr/bin/env bash
# macOS system defaults — captures machine-level settings that aren't files and
# therefore can't be symlinked by install.sh. Idempotent; safe to re-run.
#
# Usage: ./macos.sh   (then log out and back in for key-repeat to take effect)
set -euo pipefail

echo "==> keyboard"
# Key repeat: fastest practical speed (2 = GUI slider minimum, ~30ms/repeat).
defaults write -g KeyRepeat -int 2
# Delay before a held key starts repeating (~300ms). Proven value — high enough
# that normal typing never triggers accidental repeats.
defaults write -g InitialKeyRepeat -int 20
# Hold-to-repeat instead of the accent/diacritic popup — essential for vim hjkl.
defaults write -g ApplePressAndHoldEnabled -bool false

cat <<'EOF'

Done. Key-repeat settings are read at login, so log out and back in (or restart)
for them to take effect. ApplePressAndHoldEnabled applies to apps on next launch.
EOF
