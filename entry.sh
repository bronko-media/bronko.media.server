#!/usr/bin/env sh
set -eu

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

mkdir -p "${PUMA_RUN_DIR:-tmp/puma}"
bundle exec rake db:migrate
exec bundle exec puma -b tcp://0.0.0.0:4567
