# TODO

## Next release: install numr-cli from inside the plugin, then request standard installation

The listing is "Manual setup" because `numr-cli` is an external dependency.
Omarchy has a native way to close that gap; wire it in and ask the marketplace
to flip the listing to standard installation.

1. In `Overlay.qml`, when `numr-cli` is missing (`serverBroken`), replace the
   hint with: "numr is not installed yet · Enter installs it with Omarchy
   (AUR numr-bin)". Enter runs
   `Util.execArgv(["omarchy-launch-floating-terminal-with-presentation", "omarchy-pkg-aur-add numr-bin"])`
   and dismisses the overlay. This is the same flow Omarchy uses in
   `omarchy-install-and-launch`: a floating terminal with the Omarchy logo,
   yay asks for the sudo password there, "Done" at the end. Nothing is
   installed without the keypress; the plugin itself never references sudo,
   yay or pacman (the marketplace scanner flags literal `yay -S` / `pacman -S`
   and files named install/setup, so keep it to `omarchy-pkg-aur-add`).
   `omarchy-pkg-aur-add` exists in Quattro upstream and in the omarchy-mac fork.
2. Availability is re-checked on every open, so the next summon after the
   install works without a shell restart. Without AUR access the terminal
   shows the error and the hint stays.
3. README: replace the "install numr-bin" sentence with the in-plugin flow,
   keep the manual `yay` wording out (package name only).
4. Bump `version` in `manifest.json`, tag, push.
5. Marketplace: open the "Verify or update a listed plugin" form with
   "Verify and publish a newer upstream commit" and the new full HEAD SHA,
   and in the same request ask for standard installation ("Verify the listed
   snapshot and enable standard installation" acknowledgment): `omarchy plugin
   add … --enable` installs and enables the plugin, and the runtime dependency
   is installed on demand through Omarchy's own installer with explicit consent.

## Later

- Upstream PR to omarchy: a generic prefix trigger in `omarchy.menu`
  (`"prefix":"="` in JSONC plus `$QUERY` substitution in `action`) so typing
  `=2+2` in the stock menu opens the calculator. Today the menu has no hook.
- Optional `SUPER + =` binding in the README as the one-chord Spotlight-style key.
- numr-core follow-ups (separate repo): home currency for bare numbers
  (`100 in eur`), currency pair rate queries (`eur/ils`), `shekel` alias.
