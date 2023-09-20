# bronko.media.server

[![🤖 Rubocop](https://github.com/bronko-media/bronko.media.server/actions/workflows/rubocop.yml/badge.svg)](https://github.com/bronko-media/bronko.media.server/actions/workflows/rubocop.yml)

## General

This is an app to handle your image collection.
It is a ruby sinatra web app bundled with bootstrap, jquery and fancybox.

## Install

    bundle config set --local path 'vendor/bundle'
    bundle install

### DB

    bundle exec rake db:create
    bundle exec rake db:migrate

### Start

    bundle exec puma

### Build index

To index your images run `curl -v http://localhost:4567/indexer` or use the `/indexer` path from inside the app.
The `/indexer` path will get no output at the moment, but will report when finished.
This could take a while, depending on the size of your collection.

Alternatively you can use the `helper.rb`.

    bundle exec ruby helper.rb --index

You can see the progress on the console or from `docker logs bronko.media.server -f`

All png, jpg, jpeg, gif and several movie files will be indexed into a database.
Thumbs will be created and saved. They will be referenced only by their md5 hashed path.
The files in the source stay untouched. Only their meta will be saved in the database.

## Folders

Images will be found underneath `data/images`.
The sqlite3 database will be saved in `data/db`, also mysql is supported.
The thumbnails will be saved in `public/images/thumbs`
The sample Config can be found in `config/settings.yml`

The folders can be configured in settings.
But be aware that the default locations might be used somewhere in the code.
I am in early development and might hardcode or move folders.

## Docker

### Build

There is a Dockerfile to build a container. This can be done with:

    cd bronko.media
    docker build -t bronko.media.server .

### Docker Compose

For docker-compose see `docker-compose.yaml`
