#!/bin/sh
# Regenerate docs/hero.png, docs/notes.png and preview.png: installs the working copy into the
# running omarchy-shell, opens the overlay on workspace 3 with demo notes, captures with grim.
# Hyprland 0.57+ (Lua dispatchers), grim, magick, rsync.
# Restores the notes file and the workspace afterwards.
set -eu
S=$(mktemp -d); ID=io.github.nasedkinpv.numr; NOTES=$HOME/.config/numr/default.numr
REPO=$(cd "$(dirname "$0")/.." && pwd)
ws() { hyprctl dispatch "hl.dsp.focus({ workspace = \"$1\" })" >/dev/null; }
rsync -a --delete --exclude .git "$REPO/" ~/.config/omarchy/plugins/$ID/
omarchy-restart-shell >/dev/null 2>&1 || true; sleep 5
cp "$NOTES" "$S/notes-backup.numr"
trap 'cp "$S/notes-backup.numr" "$NOTES"; ws 1' EXIT
ws 3; sleep 0.8
# park the pointer in the bottom-right corner, out of the card crop
hyprctl dispatch 'hl.dsp.cursor.move({ x = 3000, y = 1900 })' >/dev/null; sleep 0.5
printf '' > "$NOTES"; sleep 0.8
omarchy-shell shell summon $ID '{"expr":"20% of 150 + $30 in eur"}' >/dev/null; sleep 1.5; grim "$S/shot-hero.png"
printf '# Lisbon, 4 nights\nhotel = 4 * $145\nflights = $380\nhotel + flights\n' > "$NOTES"; sleep 0.8
omarchy-shell shell summon $ID '{"expr":"_ / 2 in eur"}' >/dev/null; sleep 1.5; grim "$S/shot-notes.png"
omarchy-shell shell summon $ID '{"expr":""}' >/dev/null; sleep 1.5; grim "$S/shot-empty.png"
omarchy-shell shell hide $ID >/dev/null
magick "$S/shot-hero.png"  -crop 1400x700+812+360  +repage "$REPO/docs/hero.png"
magick "$S/shot-notes.png" -crop 1400x843+812+400  +repage "$REPO/docs/notes.png"
magick "$S/shot-hero.png"  -crop 1600x1000+712+300 +repage "$REPO/preview.png"
