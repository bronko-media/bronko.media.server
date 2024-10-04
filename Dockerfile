FROM docker.io/library/ruby:3.3.5-slim-bookworm AS build

RUN apt update && apt install -y \
      ffmpeg \
      g++ \
      gcc \
      imagemagick \
      libc-dev \
      libffi-dev \
      libgcrypt-dev \
      libmariadb-dev \
      libstdc++-12-dev \
      libxml2-dev \
      libxslt-dev \
      make \
      tzdata \
      xz-utils

COPY Gemfile /

RUN bundle config set path.system true \
    && bundle config set jobs $(nproc) \
    && bundle config set without 'development test' \
    && bundle install --gemfile=/Gemfile

###############################################################################

FROM docker.io/library/ruby:3.3.5-slim-bookworm AS final

LABEL org.label-schema.maintainer="bronko.media" \
      org.label-schema.vendor="bronko.media" \
      org.label-schema.url="https://github.com/bronko-media/bronko.media.server" \
      org.label-schema.name="bronko.media.server" \
      org.label-schema.license="BSD-3-Clause" \
      org.label-schema.vcs-url="https://github.com/bronko-media/bronko.media.server" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.dockerfile="/Dockerfile"

RUN apt update && apt upgrade -y \
    && apt install -y ffmpeg imagemagick tzdata xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/local/lib/ruby/gems/*/cache/*

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Dockerfile /

ENV RACK_ENV production
ENV APP_HOME /bronko.media

RUN mkdir $APP_HOME
WORKDIR $APP_HOME
ADD . $APP_HOME

EXPOSE 4567

ENTRYPOINT ["/bronko.media/entry.sh"]
