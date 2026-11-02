#!/bin/bash
# Post-install hardening required by JTL-Shop:
# delete install/ and make config read-only for the web server.
# Safe to re-run. Called by entrypoint; can also be run by hand: jtl-post-install
set -e

ROOT=/var/www/html
CONFIG=$ROOT/includes/config.JTL-Shop.ini.php

# Same check JTL installer uses: config defines BLOWFISH_KEY.
if ! { [ -f "$CONFIG" ] && grep -q "BLOWFISH_KEY" "$CONFIG"; }; then
    echo "[post-install] shop not installed yet, nothing to do"
    exit 0
fi

if [ -d "$ROOT/install" ]; then
    rm -rf "$ROOT/install"
    echo "[post-install] removed $ROOT/install"
fi

# root owns, www-data may only read -> PHP can neither rewrite nor chmod it.
chown root:www-data "$CONFIG"
chmod 0640 "$CONFIG"
echo "[post-install] locked $CONFIG (root:www-data 0640)"
