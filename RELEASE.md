# How to make a release

Initiate a Release Pull Request (PR). Ensure that the release branch includes the version in its name, as this will be utilized as the 'future_version' for the GitHub changelog generator.

See Rakefile

```ruby
config.future_release = `git rev-parse --abbrev-ref HEAD`.strip.split('-', 2).last
```

Generate Changelog

```shell
export RELEASE_VERSION="X.Y.Z"
git switch main
git pull -r
git switch -c release-v$RELEASE_VERSION

bundle config set --local path vendor/bundle
bundle config set --local with 'development'
bundle install

CHANGELOG_GITHUB_TOKEN="token_MC_tokenface" bundle exec rake changelog
```

Update Version app.rb

```ruby
module BronkoMedia
  VERSION = 'v0.4.0'
end
```

Commit & Push

```shell
git commit -am "Release v${RELEASE_VERSION}"
git push origin release-v$RELEASE_VERSION
```

After the merge do:

```shell
git switch main
git pull -r
git tag v$RELEASE_VERSION
```
