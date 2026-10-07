# Development

## Local development with SQLite

Run commands from the project root with the Ruby version in `.ruby-version`.
Development uses `config/settings.development.yml` to override the production database settings.
The web app, migrations, and CLI share this configuration when `RACK_ENV=development` is set.
MySQL remains the default outside development.

```bash
rvm use 3.4.4
bundle config set --local path 'vendor/bundle'
bundle config set --local with 'development test'
bundle install

mkdir -p data/db data/images public/images/thumbs tmp/puma
export RACK_ENV=development
bundle exec rake db:migrate
bundle exec puma -b tcp://127.0.0.1:4567
```

Open http://localhost:4567 in your browser.
SQLite creates `data/db/development.sqlite3` during migration; no database server or credentials are needed.
The database and its SQLite journal files are ignored by Git.
ImageMagick and FFmpeg are required for thumbnail generation.
The Gemfile still includes `mysql2` for production, so installing dependencies also requires MySQL client libraries.

To build the local media index:

```bash
RACK_ENV=development bundle exec ruby helper.rb --index
```

## Create migrations

```bash
RACK_ENV=development bundle exec rake db:create_migration NAME=something_else
```

## Docker Build

```bash
cd bronko.media.server
docker build -t bronko.media.server .
```

## Application structure

`app.rb` configures Sinatra and maps HTTP requests to services.
`config/boot.rb` loads dependencies, settings, models, and services for both the web application and `helper.rb`.
`BronkoMedia::Database.options` supplies the shared database configuration.

Models live in `lib/bronko_media/models`, while application operations live in `lib/bronko_media/services`.
Services receive settings and a logger explicitly and do not send HTTP responses or redirects.
`lib/bronko_media/web_helpers.rb` prepares pagination and folder data and handles HTTP parameter validation.
Templates receive their database results through locals.

Single and batch image operations share the same move and delete implementations.
Deleting an image also removes its thumbnail.
If a database update fails while moving an image, the service attempts to restore its original file location.
This recovery is not an atomic transaction across the filesystem and database.

## Tests

```bash
bundle exec ruby test.rb
bundle exec rake test
bundle exec rake rubocop
node --test test/*_test.js
```

Tests use a separate in-memory SQLite database and temporary media files.
They cover HTTP responses, template rendering, file cleanup, indexing, and failed database updates during image moves.
Tag filtering is tested with SQLite; the MySQL implementation and actual ImageMagick/FFmpeg thumbnail generation
require separate integration checks.
Indexing and duplicate scans still run synchronously through their existing GET endpoints.

## Frontend

The application uses Bootstrap 5.3.3 with its bundled Popper dependency.
Bootstrap 4 and the `bootstrap_version` setting have been removed.
Remove `bootstrap_version` from existing custom settings files; it no longer selects frontend assets.
JavaScript uses native DOM events and fetch; jQuery is not required.
