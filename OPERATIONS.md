# Running and backing up bronko.media.server

## Container user and persistent storage

The image runs as UID/GID **1001:1001**, without root privileges. Compose supports
`PUID` and `PGID` through its `user` setting (the previous UID environment variables
had no effect). For a new installation, create the media directories as the user
who will own the files, then use that user's numeric IDs:

```sh
mkdir -p data/images public/images/thumbs
printf 'PUID=%s\nPGID=%s\n' "$(id -u)" "$(id -g)" > .env
docker compose up -d
```

For an existing installation, choose IDs that already have read/write access to
both bind mounts. Correct ownership/ACLs deliberately if needed; startup does not
recursively change the ownership of your collection. The settings file must be
readable by that user. The database container manages its own permissions.

A one-shot `bronko.media.tls` helper initializes two named volumes: private MySQL
server certificates and a public CA certificate. This initializer runs as
root to assign the database key to MySQL's UID 999. The application receives only
the public CA and verifies the database certificate and hostname via `DB_SSL_CA`.
This avoids the TLS errors caused by newer Alpine clients rejecting MySQL's
self-signed, automatically generated hostname. The server certificate is valid
for `bronko.media.db` for ten years. For an external database, supply its CA and
hostname instead; do not disable verification.

The helper reuses existing certificates and refuses a certificate expiring within
24 hours. To rotate these internal certificates, stop the deployment with
`docker compose down` (without `--volumes`), remove **only** this project's
`mysql_tls` and `mysql_ca` volumes, and start it again. Never remove the database
volume/directory. A fresh restore generates a new CA; database contents do not
depend on the old TLS keys.

Compose persists originals in `data/images`, thumbnails in `public/images/thumbs`,
and MySQL in `tmp/testdb/config`. The database location is retained for existing
installations. Do not delete it when cleaning temporary files. Settings are mounted
read-only. Runtime files and schema dumps go to `/tmp` inside the application
container; local development continues to use `tmp/puma` and `db/schema.rb`.

**Before recreating an old application container**, copy any existing thumbnails
out of its writable layer (or regenerate them later with the indexer):

```sh
mkdir -p public/images/thumbs
docker compose cp bronko.media.server:/bronko.media/public/images/thumbs/. public/images/thumbs/
```

Ensure the selected UID can write those copied files. Binding the new directory
hides thumbnails that previously lived only inside the container.

Migrations must succeed before Puma starts. Puma replaces the entrypoint process,
so container stop signals reach the server. The image healthcheck checks HTTP on
port 4567; inspect `docker compose ps` and `docker compose logs` if startup fails.
An unhealthy container is not automatically restarted by Docker's restart policy.
Explicit commands bypass migration/startup, for example:

```sh
docker compose run --rm --no-deps bronko.media.server ruby --version
```

## MySQL backups

Run `script/backup` from the project directory on a Linux host with Bash, Docker
Compose v2, GNU coreutils and `flock` (util-linux). It supports the supplied MySQL Compose layout and
refuses customized media paths or a non-production environment. Use an image
built from this revision or later. `COMPOSE_FILE`/`COMPOSE_PROJECT_NAME` can select
a deployment; `COMPOSE_BIN` can select a standalone Compose executable.

```sh
script/backup create "backups/$(date +%Y%m%d-%H%M%S)"
```

The script stops a running application, takes a logical MySQL dump, archives
originals and thumbnails, and restarts the application even if backup fails.
An already stopped application stays stopped. A checkout-level lock prevents
overlapping backup/restore commands. Do not operate on the same deployment from
multiple checkouts at once. MySQL must be running. Pause all
other writers (CLI indexers, import jobs, other app instances and external file
changes) for the whole operation; stopping this Compose service cannot stop them.
The downtime includes copying the complete collection.

A completed backup contains `database.sql`, `media.tar.gz`, `settings.yml`, a format
marker and SHA-256 checksums. Incomplete backups are removed and existing backups
are never overwritten. Symlinks and special files in the media trees are rejected.
The SQL dump preserves IDs, favorites, tags and migration versions; reindexing
alone cannot recover that metadata. Backups include database credentials in the
settings file and private media: the script creates them with restrictive host
permissions. Copy completed backups to separate storage. Back up deployment files
(Compose overrides, `.env`, secret sources and the exact image tag/digest) separately.

## Restore into an empty installation

Use only trusted backups: SQL restoration executes the statements in the dump.
Checksums detect damage, not malicious replacements. Restore first using the same
application revision and MySQL version, then upgrade separately.

1. Prepare a separate checkout/deployment with empty database, originals and
   thumbnail directories. Configure its database credentials and bind-mount
   ownership as above. Review the saved `settings.yml`; restore settings manually,
   retaining credentials/hostnames appropriate for the destination. The script
   deliberately does not overwrite the destination's configuration.
2. Start **only** MySQL and wait for it to become healthy:

   ```sh
   docker compose up -d bronko.media.db
   docker compose ps
   ```

3. Restore before starting the application (startup migrations would populate the
   empty database):

   ```sh
   script/backup restore /absolute/path/to/backup
   docker compose up -d
   ```

The script checks checksums and archive paths before extracting, refuses a running
application, a populated database, or nonempty media directories, and leaves the
application stopped after restoring. Files receive the destination container's
UID/GID, allowing restoration under a different host user. If a restore fails
partway through, keep that destination stopped, inspect the error and prepare a
new empty destination before retrying; a filesystem and SQL import are not one
atomic transaction. Never delete the source installation to prepare a restore.

Check favorites, tags and image downloads in the restored app. Keep the source
installation and backup until this verification succeeds.

## SQLite and custom installations

The Compose backup script is specifically for MySQL. For a local SQLite deployment,
stop every application/CLI writer, then copy the database **together with any
`-wal` and `-shm` sidecars**, originals, thumbnails and settings as one offline
snapshot. Restore that complete set into an empty installation before starting it,
using the same paths and compatible app version. Do not copy a live SQLite database
file alone. Custom storage paths require a correspondingly adapted backup process.

## Automated recovery test

```sh
docker build -t ci/dummy:test .
test/operations/run
```

The test uses a unique Compose project and disposable named volumes. It creates a
real image/index with Unicode tags and a favorite, backs it up, destroys the test
volumes, restores into an empty database, and verifies the original checksum and
metadata. It also checks non-root execution, verified TLS, Puma as PID 1, failed-backup
recovery, long filenames, overwrite refusal and
thumbnail persistence after container recreation. The CI runs this test alongside
the unit and database/media integration suites. It does not use production bind
mounts. Local Podman users can set `COMPOSE_BIN=podman-compose` and
`BRONKO_TEST_IMAGE=localhost/bronko-ops:test`.
