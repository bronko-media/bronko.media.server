# Development

## Install

```bash
bundle config set --local path 'vendor/bundle'
bundle config --local build.mysql2 "--with-ldflags=-L/opt/homebrew/Cellar/zstd/1.5.7/lib"
bundle install
```

### Initialize DB

```bash
bundle exec rake db:create
bundle exec rake db:migrate
```

### Start App

```bash
bundle exec puma
```

## Create Migrations

```bash
bundle exec rake db:create_migration NAME=something_else
```

## Install MySQL on macOS

```bash
brew install mysql
brew services start mysql


mysql -u root
> CREATE USER 'bronko'@'localhost' IDENTIFIED BY 'password';
> GRANT ALL PRIVILEGES ON BronkoMediaServer.* TO 'bronko'@'localhost';
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
```

Tests use a separate in-memory SQLite database and temporary media files.
They cover HTTP responses, template rendering, file cleanup, indexing, and failed database updates during image moves.
The MySQL-specific tag filter and actual ImageMagick/FFmpeg thumbnail generation require separate integration checks.
Indexing and duplicate scans still run synchronously through their existing GET endpoints.
