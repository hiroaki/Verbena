FROM ruby:3.2.0

RUN apt-get update -qq \
  && apt-get install -yq --no-install-recommends \
      vim \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && truncate -s 0 /var/log/*log

ENV LANG=C.UTF-8
ENV TZ=Asia/Tokyo
ENV APP_ROOT=/verbena

RUN useradd -m rails && mkdir $APP_ROOT && chown -R rails:rails $APP_ROOT \
  && mkdir -p /usr/local/bundle \
  && chmod 755 /usr/local/bundle \
  && chown -R rails:rails /usr/local/bundle

USER rails
WORKDIR $APP_ROOT

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENTRYPOINT ["/bin/bash", "/verbena/entrypoint.sh"]
CMD ["bundle", "exec", "rails", "c"]
