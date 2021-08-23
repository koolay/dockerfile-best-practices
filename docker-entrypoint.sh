#!/usr/bin/env bash
set -e

if [ "$1" = 'myapp' ]; then
	echo "[entrypoint] gosu run app"
	exec gosu app "$@"
fi
exec "$@"

