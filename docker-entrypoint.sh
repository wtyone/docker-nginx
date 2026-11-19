#!/bin/sh
set -eu

if [ "${1:-}" = nginx ]; then
    for name in conf html; do
        target="/opt/nginx/$name"
        mkdir -p "$target"
        if [ -z "$(ls -A "$target")" ]; then
            cp -R "/usr/local/share/nginx-defaults/$name/"* "$target/"
        fi
    done
fi

exec "$@"
