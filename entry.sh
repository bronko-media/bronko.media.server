#!/usr/bin/env sh

bundle exec rake db:migrate
bundle exec puma -b tcp://0.0.0.0:4567
