#!/usr/bin/env bash

bundle exec rake db:migrate

# bundle exec rackup --host 0.0.0.0 -p 4567
bundle exec puma -b tcp://0.0.0.0:4567
