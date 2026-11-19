#!/bin/sh
set -eu

cd "$(dirname "$0")"
www_uid=$(id -u www-data)
www_gid=$(id -g www-data)
export WWW_DATA_USER="$www_uid:$www_gid"

# Initialize only missing mount directories. Keep existing data ownership.
for name in conf logs html; do
    path="/opt/nginx/$name"
    if [ ! -d "$path" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            install -d -m 0755 -o "$www_uid" -g "$www_gid" "$path"
        else
            sudo install -d -m 0755 -o "$www_uid" -g "$www_gid" "$path"
        fi
    fi
done

exec docker compose up -d "$@"
