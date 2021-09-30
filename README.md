# Elixir/Phoenix on Alpine Linux

## Prior Work

[bitwalker]: https://github.com/bitwalker/

This project is based entirely on the following projects from [bitwalker][bitwalker].

- alpine-erlang
- alpine-elixir
- alpine-elixir-phoenix

It combines these three repositories (images) into a single one. Also, it
builds for the `linux/amd64,linux/arm/v7` platforms. Building for
`linux/arm/v7` was the main motivation for the fork.

The description below is taken (and slightly modified) from the original
`alpine-elixir-phoenix` repo.

## Overview

This Dockerfile provides everything you need to run your Phoenix application in Docker out of the box.

See the VERSION file to check the current versions of Alpine, Erlang and
Elixir. Nodejs and yarn from Alpine, Hex and Rebar. It can handle compiling
your Node and Elixir dependencies as part of it's build.

## Usage

NOTE: This image is intended to run in unprivileged environments, it sets the home directory to `/opt/app`, and makes it globally
read/writeable. If run with a random, high-index user account (say 1000001), the user can run an app, and that's about it. If run
with a user of your own creation, this doesn't apply (necessarily, you can of course implement the same behaviour yourself).
It is highly recommended that you add a `USER default` instruction to the end of your Dockerfile so that your app runs in a non-elevated context.

To boot straight to a prompt in the image:

```
$ docker run --rm -it --user=1000001 ghcr.io/eglimi/alpine-elixir-phoenix iex
Erlang/OTP 24 [erts-12.0.3] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [jit:no-native-stack]

Interactive Elixir (1.12.2) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)>
```

Extending for your own application:

```dockerfile
FROM ghcr.io/eglimi/alpine-elixir-phoenix:latest

# Set exposed ports
EXPOSE 5000
ENV PORT=5000 MIX_ENV=prod

# Cache elixir deps
ADD mix.exs mix.lock ./
RUN mix do deps.get, deps.compile

# Same with npm deps
ADD assets/package.json assets/
RUN cd assets && \
    yarn install

ADD . .

# Run frontend build, compile, and digest assets
RUN cd assets/ && \
    yarn run deploy && \
    cd - && \
    mix do compile, phx.digest

USER default

CMD ["mix", "phx.server"]
```

It is recommended when using this that you have the following in `.dockerignore` when running `docker build`:

```
_build
deps
assets/node_modules
test
```

This will keep the payload smaller and will also avoid any issues when compiling dependencies.

### Multistage Docker Builds

You can also leverage [docker multistage build](https://docs.docker.com/develop/develop-images/multistage-build/) and [bitwalker/alpine-elixir](https://github.com/bitwalker/alpine-elixir) to lower your image size significantly.

An example is shown below:

```dockerfile
FROM ghcr.io/eglimi/alpine-elixir-phoenix:latest AS phx-builder

WORKDIR /tmp/build

ENV NODE_ENV=production \
    MIX_ENV=prod \

# Cache elixir deps
ADD mix.exs mix.lock ./
RUN mix do deps.get, deps.compile

# Same with npm deps
ADD assets/package.json assets/
RUN cd assets && \
    yarn install

ADD . .

# Run frontend build, compile, and digest assets
RUN cd assets/ && \
    yarn run deploy && \
    cd - && \
    mix do compile, phx.digest, release --overwrite

# Final image
FROM alpine:3.14.0

# Installing some tools for debugging in a production environment
RUN \
    apk --no-cache --update-cache --available upgrade \
    && apk add --no-cache --update-cache \
	bash curl libstdc++ ca-certificates ncurses openssl pcre unixodbc zlib netcat-openbsd bind-tools \
    && update-ca-certificates --fresh

ENV LANG=C.UTF-8

WORKDIR /opt/app

COPY --from=phx-builder /tmp/build/_build/prod/rel .

USER default

CMD ["./my_app/bin/my_app", "start"]
```

## License

MIT
