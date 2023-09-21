# Install

```bash
bundle config set --local path 'vendor/bundle'
bundle install
```

## Initialize DB

```bash
bundle exec rake db:create
bundle exec rake db:migrate
```

## Start App

```bash
bundle exec puma
```

# Create Migrations

```bash
bundle exec rake db:create_migration NAME=something_else
```

# Install MySQL on macOS

```bash
brew install mysql
brew services start mysql


mysql -u root
> CREATE USER 'bronko'@'localhost' IDENTIFIED BY 'password';
> GRANT ALL PRIVILEGES ON BronkoMediaServer.* TO 'bronko'@'localhost';
```

# Docker Build

```bash
cd bronko.media.server
docker build -t bronko.media.server .
```
