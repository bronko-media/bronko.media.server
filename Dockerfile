FROM ruby:4.0.7-alpine AS build

RUN apk add --no-cache \
      ffmpeg \
      g++ \
      gcc \
      imagemagick \
      libc-dev \
      libffi-dev \
      libgcrypt \
      mariadb-connector-c-dev \
      libstdc++ \
      libxml2-dev \
      libxslt-dev \
      make \
      tzdata \
      xz

COPY Gemfile /
COPY Gemfile.lock /

RUN bundle config set path.system true \
    && bundle config set jobs $(nproc) \
    && bundle config set without 'development test' \
    && bundle install --gemfile=/Gemfile

###############################################################################

FROM ruby:4.0.7-alpine AS final

LABEL org.label-schema.maintainer="bronko.media" \
      org.label-schema.vendor="bronko.media" \
      org.label-schema.url="https://github.com/bronko-media/bronko.media.server" \
      org.label-schema.name="bronko.media.server" \
      org.label-schema.license="BSD-3-Clause" \
      org.label-schema.vcs-url="https://github.com/bronko-media/bronko.media.server" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.dockerfile="/Dockerfile"

RUN apk add --no-cache ffmpeg imagemagick tzdata xz mariadb-connector-c openssl \
    && rm -rf /usr/local/bundle/cache/*

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Dockerfile /

ENV RACK_ENV=production
ENV APP_HOME=/bronko.media
ENV PUMA_RUN_DIR=/tmp/bronko-puma
ENV SCHEMA=/tmp/bronko-schema.rb

RUN addgroup -g 1001 bronko \
    && adduser -D -u 1001 -G bronko bronko \
    && mkdir -p "$APP_HOME"
WORKDIR $APP_HOME
COPY . $APP_HOME
RUN mkdir -p data/images data/db public/images/thumbs tmp/puma \
    && chown -R bronko:bronko data public/images/thumbs tmp

USER bronko:bronko

EXPOSE 4567

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:4567/")).code == "200" ? 0 : 1)'

ENTRYPOINT ["/bronko.media/entry.sh"]
