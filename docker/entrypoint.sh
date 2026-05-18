#!/bin/bash
set -e

PERSIST_DIR=/persist
CONFIG_SRC=/var/www/html/includes/config.JTL-Shop.ini.php
CONFIG_PERSIST=${PERSIST_DIR}/config.JTL-Shop.ini.php

mkdir -p "$PERSIST_DIR"

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
