FROM ruby:3.2.2-alpine

RUN apk add --update --no-cache \
      binutils-gold \
      build-base \
      ffmpeg \
      g++ \
      gcc \
      graphicsmagick \
      imagemagick \
      jpeg-dev \
      libc-dev \
      libffi-dev \
      libgcrypt-dev \
      libjpeg-turbo-dev \
      libpng-dev \
      libstdc++ \
      libxml2-dev \
      libxslt-dev \
      linux-headers \
      make \
      mysql-dev \
      sqlite \
      sqlite-dev \
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
