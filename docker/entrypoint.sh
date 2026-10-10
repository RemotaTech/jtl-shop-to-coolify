#!/bin/bash
set -e

PERSIST_DIR=/persist
CONFIG_SRC=/var/www/html/includes/config.JTL-Shop.ini.php
CONFIG_PERSIST=${PERSIST_DIR}/config.JTL-Shop.ini.php

mkdir -p "$PERSIST_DIR"

# Seed volume-mounted dirs from image snapshot if empty (first boot).
# Empty named volume overlays image content -> must restore baked files.
seed_dir() {
    target="$1"
    seed="$2"
    mkdir -p "$target"
    if [ -d "$seed" ] && [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
        echo "[entrypoint] seeding $target from image snapshot"
        cp -a "$seed/." "$target/"
    fi
    chown www-data:www-data "$target"
}

seed_dir /var/www/html/templates /opt/jtl-seed/templates
seed_dir /var/www/html/plugins   /opt/jtl-seed/plugins
seed_dir /var/www/html/downloads /opt/jtl-seed/downloads
seed_dir /var/www/html/uploads   /opt/jtl-seed/uploads

# Refresh NOVA when image ships a different version than the volume.
# seed_dir only fills empty volumes -> shop upgrades would keep old NOVA.
# NOVA is vendor code: customizations belong in a child template.
nova_version() {
    sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$1/template.xml" 2>/dev/null | head -n1
}

refresh_nova() {
    seed=/opt/jtl-seed/templates/NOVA
    target=/var/www/html/templates/NOVA
    [ -d "$seed" ] || return 0
    new=$(nova_version "$seed")
    old=$(nova_version "$target")
    if [ -z "$new" ] || [ "$new" = "$old" ]; then
        return 0
    fi
    echo "[entrypoint] updating NOVA template ${old:-none} -> $new"
    if [ -d "$target" ]; then
        backup="${PERSIST_DIR}/NOVA.bak-${old:-unknown}"
        rm -rf "$backup"
        mv "$target" "$backup"
        echo "[entrypoint] old NOVA backed up to $backup"
    fi
    cp -a "$seed" "$target"
    chown -R www-data:www-data "$target"
    # Drop compiled Smarty output so pages rebuild against new NOVA.
    find /var/www/html/templates_c -mindepth 1 -type f ! -name .htaccess -delete 2>/dev/null || true
}

refresh_nova

if [ -f "$CONFIG_PERSIST" ]; then
    echo "[entrypoint] restoring config.JTL-Shop.ini.php from /persist"
    cp "$CONFIG_PERSIST" "$CONFIG_SRC"
    chown www-data:www-data "$CONFIG_SRC"
fi

if [ -f "$CONFIG_SRC" ] && [ ! -f "$CONFIG_PERSIST" ]; then
    echo "[entrypoint] backing up freshly-installed config to /persist"
    cp "$CONFIG_SRC" "$CONFIG_PERSIST"
fi

(
    while true; do
        sleep 60
        if [ -f "$CONFIG_SRC" ]; then
            if ! cmp -s "$CONFIG_SRC" "$CONFIG_PERSIST" 2>/dev/null; then
                cp "$CONFIG_SRC" "$CONFIG_PERSIST"
                echo "[entrypoint] config.JTL-Shop.ini.php changed, synced to /persist"
            fi
        fi
    done
) &

exec apache2-foreground
