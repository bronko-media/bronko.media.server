FROM ruby:3.3.4-slim-bookworm

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
      xz-utils \
      && rm -rf /var/lib/apt/lists/*

ENV RACK_ENV production
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
