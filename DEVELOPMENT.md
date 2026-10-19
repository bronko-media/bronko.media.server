# Development

## Local development with SQLite

Run commands from the project root with the Ruby version in `.ruby-version`.
Ruby 4.x and Bundler 4 are required; Docker and `.ruby-version` currently pin Ruby 4.0.7.
CI uses `.ruby-version` through `ruby/setup-ruby`.
Development uses `config/settings.development.yml` to override the production database settings.
The web app, migrations, and CLI share this configuration when `RACK_ENV=development` is set.
MySQL remains the default outside development.

```bash
rvm use 4.0.7
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
Upload and indexing tests exercise ImageMagick and FFmpeg and require both locally and in CI.
The separate integration suite runs the real migration chain against a temporary SQLite
file or a newly created MySQL database. It exercises PNG/JPEG/GIF and video processing,
HTTP multipart uploads, exact JSON tag matching, rescans, folder cleanup, database-error
recovery, and simultaneous moves to the same destination. Scans use three worker threads.
Both adapters run in CI; JavaScript tests also run in CI.
Indexing and duplicate scans still run synchronously through their existing GET endpoints.

### Database and media integration tests

ImageMagick and FFmpeg must be installed. Run the suite separately from the in-memory
unit tests; it builds its schema from `db/migrate`, not a copied test schema:

```bash
bundle exec ruby test/integration/run.rb
# Equivalent Rake entry point:
bundle exec rake test:integration
```

To run the same suite against an isolated MySQL instance matching Docker Compose:

```bash
docker run --detach --rm --name bronko-integration-mysql \
  --env MYSQL_ROOT_PASSWORD=bronko_test_only --env MYSQL_ROOT_HOST=% \
  --publish 127.0.0.1:33060:3306 mysql:8.0.34
# Wait until the server reports that it is ready:
docker logs bronko-integration-mysql

BRONKO_TEST_ADAPTER=mysql2 \
BRONKO_TEST_MYSQL_HOST=127.0.0.1 \
BRONKO_TEST_MYSQL_PORT=33060 \
BRONKO_TEST_MYSQL_USER=root \
BRONKO_TEST_MYSQL_PASSWORD=bronko_test_only \
bundle exec ruby test/integration/run.rb

docker stop bronko-integration-mysql
```

Podman can be substituted for Docker. The test account needs permission to create and
drop databases and create triggers. The suite generates a unique `bronko_integration_*`
database, runs all migrations, and removes that database and temporary files after the
run, including failed tests. It never takes a database name from application settings
or `DATABASE_URL`. Missing tools, connection failures, and migration failures fail the
suite rather than silently skipping integration coverage.

Migration checks cover a clean installation, upgrading the pre-bigint schema while
retaining tags and favorites, and refusal to roll back sizes that would overflow.
The file-operation failure tests use actual SQLite/MySQL database triggers, not mocked
persistence. CI requires both the regular test job and integration job before Dependabot
auto-merge can be enabled.

## Frontend

The application uses Bootstrap 5.3.3 with its bundled Popper dependency.
Bootstrap 4 and the `bootstrap_version` setting have been removed.
Remove `bootstrap_version` from existing custom settings files; it no longer selects frontend assets.
JavaScript uses native DOM events and fetch; jQuery is not required.

## Safe file operations

Media paths are normalized against `originals_path`. Requests outside that root,
paths containing `..`, and symlinks below the root are rejected. The media root itself
cannot be moved or deleted. Existing destinations are rejected rather than overwritten;
folder creation requires an existing parent. Storage roots must exist before use.

Mutations and scans take an advisory filesystem lock on the media root, shared by the
web application and CLI. This coordinates application workers; external programs that
change files directly do not participate in that lock.

Folder moves update existing image and folder records and relocate cached thumbnails,
preserving IDs, tags, and favorites. Folder moves across filesystem boundaries are
rejected. File moves support separate filesystems through an exclusive destination copy.
Recursive deletion removes descendant records and thumbnails. Originals are staged until
database deletion succeeds, allowing restoration after a database error. Filesystem and
database changes are still not a crash-safe distributed transaction: an interrupted process
or a failure during final cleanup can leave staged files requiring manual recovery.

The web configuration form only edits display and processing settings, validates them,
and saves via POST with a session token. Storage paths and database credentials must be
edited in the configuration file, followed by an application restart. Secrets are not
rendered into the form or sent in query strings. Configuration writes retain the file inode
to support Docker bind mounts and use a file lock to serialize writers.

## Rescanning media

Every scan reads image metadata and signatures again, even if a thumbnail already exists.
Videos are probed with FFmpeg and receive a SHA-256 content signature, byte size, and dimensions.
Reading content on each scan also catches changes with unchanged size and modification time,
but takes longer for large collections and video files. Image signatures retain their existing
ImageMagick pixel-signature semantics; video duplicates are byte-identical files, not visually
similar videos or different encodings of the same video.

Existing records are updated in place: IDs, favorites, and tags survive rescans. Unchanged
records and thumbnails are retained. Missing or empty thumbnails are rebuilt, and changed
media receives a new thumbnail via a temporary file and rename. Failed thumbnail generation
removes the stale thumbnail so the next scan retries. Unreadable media is logged; existing
records retain user metadata but their signature and dimensions are cleared until a successful
scan. Other files continue to be indexed.

Folder scans also clean removed descendants and recompute duplicate flags. Duplicate scans
reset previous flags and exclude missing or empty signatures within a database transaction.
Scans skip symlinks, hidden entries, and the configured thumbnail directory. A missing scan
root aborts before cleanup; a directory that still exists but represents an unavailable mount
cannot be distinguished from an intentionally empty collection.

Run `bundle exec rake db:migrate` in the configured environment before using this version.
The media size column now uses a 64-bit integer to accommodate videos larger than 2 GiB.

## Container and recovery tests

See [OPERATIONS.md](OPERATIONS.md#automated-recovery-test) for the isolated Compose
backup/restore test, container permissions and production operation.
