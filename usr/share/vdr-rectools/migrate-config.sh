#!/bin/sh
# Relocate legacy rectools settings out of VDR's plugin-argument directory.
# This is shared by Debian upgrades and manual installations.
set -eu

etc_vdr=${VDR_RECTOOLS_ETC_DIR:-/etc/vdr}
legacy="$etc_vdr/conf.d/vdr-rectools.conf"
canonical="$etc_vdr/vdr-rectools.conf"

# No migration needed. A broken symlink must also be taken out of conf.d.
if [ ! -e "$legacy" ] && [ ! -L "$legacy" ]; then
    exit 0
fi

# A standalone legacy file can become the canonical configuration unchanged.
# Preserve symlinks as backups: their relative targets might change on move.
if [ ! -e "$canonical" ] && [ ! -L "$canonical" ] && [ ! -L "$legacy" ]; then
    mv -- "$legacy" "$canonical"
    echo "vdr-rectools: moved legacy configuration to $canonical" >&2
    exit 0
fi

# Never overwrite the canonical configuration or an earlier backup.
backup="$etc_vdr/vdr-rectools.conf.legacy"
n=1
while [ -e "$backup" ] || [ -L "$backup" ]; do
    backup="$etc_vdr/vdr-rectools.conf.legacy.$n"
    n=$((n + 1))
done
mv -- "$legacy" "$backup"
if [ ! -L "$backup" ]; then
    chmod 600 "$backup"
fi
printf '%s\n' \
    "vdr-rectools: preserved old configuration as $backup" \
    "vdr-rectools: check custom settings against $canonical (not overwritten)." >&2
