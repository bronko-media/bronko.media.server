# Bronko Media

[![Docker Hub package][dockerhub-badge]][dockerhub-link]

[dockerhub-badge]: https://img.shields.io/badge/images%20on-Docker%20Hub-blue.svg

[dockerhub-link]: https://hub.docker.com/r/rwaffen/bronko.media

## General

Bronko Media is the maori word for collection.

This is an app to handle your image collection.
It is a ruby sinatra web app bundled with bootstrap, jquery and fancybox.

## Install

    bundle install --path vendor/gems

### DB

    bundle exec rake db:create
    bundle exec rake db:migrate

### Start

    bundle exec ruby app.rb

### Build index

To index your images run `curl -v localhost:4567/indexer` or use the `/indexer` path from inside the app.
The `/indexer` path will get no output at the moment, but will report when finished.
This could take a while, depending on the size of your collection.
You can see the progress on the console or from `docker logs bronko.media -f`

All png, jpg and jpeg files will be indexed into a sqlite3.
They will be referenced only by their md5 hashed path.

For example:

    https://bronko.media:4567/image/7299f8a29c06b9bfa30c412c6082e884

## Folders

Images will be found underneath `data/images`.
The database will be saved in `data/db`.
The thumbnails will be saved in `public/images/thumbs`

The folders can be configured in `config/settings.yml`. But be aware that the default locations might be used somewhere in the code. I am in early development and might hardcode or move folders.

## Docker

### Build

There is a Dockerfile to build a container. This can be done with:

    cd bronko.media
    docker build -t bronko.media .

### Docker Compose

For docker-compose see `docker-compose.yaml` or use this example:

    ---
    version: "3.5"
    services:
      bronko.media:
        image: rwaffen/bronko.media:develop
        container_name: bronko.media
        volumes:
          # keep db outside of container
          - /srv/data/bronko.media/db:/bronko.media/data/db

          # keep thumbnails outside of container
          - /srv/data/bronko.media/public/images:/bronko.media/public/images

          # add media files read only
          - /srv/media/Images:/app/data/images:ro
        ports:
          - 4567:4567
        restart: unless-stopped
