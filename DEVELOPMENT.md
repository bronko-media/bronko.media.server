# Create Migrations

    bundle exec rake db:create_migration NAME=something_else

# install mysql on macos

```bash
brew install mysql
brew services start mysql


mysql -u root
> CREATE USER 'bronko'@'localhost' IDENTIFIED BY 'password';
> GRANT ALL PRIVILEGES ON BronkoMediaServer.* TO 'bronko'@'localhost';
```
