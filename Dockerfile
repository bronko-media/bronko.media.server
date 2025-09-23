FROM ruby:3.4.6-alpine AS build

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

FROM ruby:3.4.6-alpine AS final

LABEL org.label-schema.maintainer="bronko.media" \
      org.label-schema.vendor="bronko.media" \
      org.label-schema.url="https://github.com/bronko-media/bronko.media.server" \
      org.label-schema.name="bronko.media.server" \
      org.label-schema.license="BSD-3-Clause" \
      org.label-schema.vcs-url="https://github.com/bronko-media/bronko.media.server" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.dockerfile="/Dockerfile"

RUN apk add --no-cache ffmpeg imagemagick tzdata xz mariadb-connector-c \
    && rm -rf /usr/local/bundle/cache/*

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Dockerfile /

ENV RACK_ENV=production
ENV APP_HOME=/bronko.media

RUN mkdir $APP_HOME
WORKDIR $APP_HOME
ADD . $APP_HOME

EXPOSE 4567

ENTRYPOINT ["/bronko.media/entry.sh"]
