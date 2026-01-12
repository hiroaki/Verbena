FROM ruby:3.4.8

RUN apt-get update -qq \
  && apt-get install -yq --no-install-recommends \
      vim \
      build-essential \
      libxml2-dev \
      libxslt1-dev \
      zlib1g-dev \
      libpq-dev \
      default-libmysqlclient-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && truncate -s 0 /var/log/*log

ENV LANG=C.UTF-8
ENV TZ=Asia/Tokyo
ENV APP_ROOT=/verbena

RUN useradd -m rails \
  && mkdir -p $APP_ROOT /usr/local/bundle \
  && chown -R rails:rails $APP_ROOT /usr/local/bundle \
  && chmod 755 /usr/local/bundle

USER rails
WORKDIR $APP_ROOT

# Copy Gemfile(s) as the rails user and install gems
COPY --chown=rails:rails Gemfile Gemfile.lock ./
RUN bundle install --jobs=4 --retry=3

# Copy application files as rails
COPY --chown=rails:rails . .

ENTRYPOINT ["/bin/bash", "/verbena/entrypoint.sh"]
CMD ["/bin/bash"]
