FROM ruby:3.1-alpine

RUN apk add --update --no-cache \
      binutils-gold \
      build-base \
      g++ \
      gcc \
      libstdc++ \
      libffi-dev \
      libc-dev \
      libxml2-dev \
      libxslt-dev \
      libgcrypt-dev \
      make \
      ffmpeg \
      graphicsmagick \
      sqlite \
      sqlite-dev \
      linux-headers \
      libpng-dev \
      jpeg-dev \
      mysql-dev \
      tzdata

ENV APP_HOME /bronko.media
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile $APP_HOME/
RUN bundle config set --local path 'vendor/bundle' && \
      bundle config set --local without 'development test' && \
      bundle install

ADD . $APP_HOME

EXPOSE 4567

CMD ["/bronko.media/entry.sh"]
