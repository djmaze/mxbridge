FROM elixir:1.6

WORKDIR /usr/src/app

COPY mix.* ./

RUN mix local.hex --force \
 && mix local.rebar --force \
 && mix deps.get \
 && mix compile

COPY . ./

RUN mix compile
