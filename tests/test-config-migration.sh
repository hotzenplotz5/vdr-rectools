#!/bin/sh
# Run with: sh tests/test-config-migration.sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/usr/share/vdr-rectools/migrate-config.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

run() { VDR_RECTOOLS_ETC_DIR="$tmp/$1" sh "$script" >/dev/null 2>&1; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# Fresh installation: no unintended file is created.
mkdir -p "$tmp/fresh/conf.d"
run fresh
[ ! -e "$tmp/fresh/vdr-rectools.conf" ] || fail 'fresh config created'

# Old-only installation: preserve settings and remove arguments seen by VDR.
mkdir -p "$tmp/legacy/conf.d"
printf 'IMPORT_DIR="/media/custom path"\n' > "$tmp/legacy/conf.d/vdr-rectools.conf"
run legacy
[ ! -e "$tmp/legacy/conf.d/vdr-rectools.conf" ] || fail 'legacy conf.d entry remains'
grep -Fqx 'IMPORT_DIR="/media/custom path"' "$tmp/legacy/vdr-rectools.conf" || fail 'settings lost'
run legacy
[ ! -e "$tmp/legacy/vdr-rectools.conf.legacy" ] || fail 'non-idempotent migration'

# Package upgrade: the newly installed conffile always takes precedence;
# previous settings are retained in a backup instead of being overwritten.
mkdir -p "$tmp/upgrade/conf.d"
printf 'AUTO_TIMER=0\n' > "$tmp/upgrade/vdr-rectools.conf"
printf 'AUTO_TIMER=1\n' > "$tmp/upgrade/conf.d/vdr-rectools.conf"
run upgrade
[ ! -e "$tmp/upgrade/conf.d/vdr-rectools.conf" ] || fail 'upgrade leaves VDR arguments'
grep -Fqx 'AUTO_TIMER=0' "$tmp/upgrade/vdr-rectools.conf" || fail 'canonical conffile overwritten'
grep -Fqx 'AUTO_TIMER=1' "$tmp/upgrade/vdr-rectools.conf.legacy" || fail 'legacy settings lost'

# Existing backup must never be overwritten on later upgrades.
printf 'AUTO_TIMER=2\n' > "$tmp/upgrade/conf.d/vdr-rectools.conf"
run upgrade
grep -Fqx 'AUTO_TIMER=1' "$tmp/upgrade/vdr-rectools.conf.legacy" || fail 'backup overwritten'
grep -Fqx 'AUTO_TIMER=2' "$tmp/upgrade/vdr-rectools.conf.legacy.1" || fail 'new backup missing'

# A symlink in conf.d is also removed (without modifying its target).
mkdir -p "$tmp/link/conf.d"
printf 'WEB_USER="admin"\n' > "$tmp/link/actual.conf"
ln -s ../actual.conf "$tmp/link/conf.d/vdr-rectools.conf"
run link
[ ! -L "$tmp/link/conf.d/vdr-rectools.conf" ] || fail 'legacy symlink remains'
[ -L "$tmp/link/vdr-rectools.conf.legacy" ] || fail 'legacy symlink lost'
grep -Fqx 'WEB_USER="admin"' "$tmp/link/actual.conf" || fail 'symlink target changed'

printf '%s\n' 'PASS: 5 config-migration scenarios'
