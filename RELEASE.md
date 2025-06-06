# How to make a release

## On a fork

Please follow these instructions carefully. Ensure that you name the branch precisely as release-vX.Y.Z since this nomenclature is crucial for obtaining the future_version in the changelog. Your attention to this specific branch naming convention is essential for accurate version tracking in the changelog.

```shell
export RELEASE_VERSION="X.Y.Z"
git switch main
git pull -r
git switch -c release-v$RELEASE_VERSION

bundle config set --local path vendor/bundle
bundle config set --local with 'release'
bundle install

CHANGELOG_GITHUB_TOKEN="token_MC_tokenface" bundle exec rake changelog
git commit -am "Release v${RELEASE_VERSION}"
git push origin release-v$RELEASE_VERSION
```

Update Version app.rb

```ruby
module BronkoMedia
  VERSION = 'v0.4.0'
end
```

Then open a PR, discuss and merge.

## After the merge, as a maintainer on upstream

```shell
git switch main
git pull -r
git tag v$RELEASE_VERSION -m "v$RELEASE_VERSION"
git push --tags
```
