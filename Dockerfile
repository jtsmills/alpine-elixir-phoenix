ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION} AS build
ARG ALPINE_MIN_VERSION
ARG ERLANG_VERSION
ARG ELIXIR_VERSION

MAINTAINER Justin Mills <me@jtsmills.com>

# Important!  Update this no-op ENV variable when this Dockerfile
# is updated with the current date. It will force refresh of all
# of the base images and things like `apt-get update` won't be using
# old cached versions when the Dockerfile is built.
ENV REFRESHED_AT=2023-09-05 \
    LANG=C.UTF-8 \
    HOME=/opt/app/ \
    TERM=xterm \
    ALPINE_MIN_VERSION=${ALPINE_MIN_VERSION} \
    ERLANG_VERSION=${ERLANG_VERSION} \
    ELIXIR_VERSION=${ELIXIR_VERSION} \
    MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex

# Add tagged repos as well as the edge repo so that we can selectively install edge packages
RUN \
    echo "@main http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MIN_VERSION}/main" >> /etc/apk/repositories \
    && echo "@community http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MIN_VERSION}/community" >> /etc/apk/repositories \
    && echo "@edge http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories

# Upgrade Alpine and base packages
RUN apk --no-cache --update-cache --available upgrade

# Install bash and Erlang/OTP deps
RUN \
    apk add --no-cache --update-cache \
	bash curl ca-certificates libgcc lksctp-tools pcre zlib-dev

# Install Elixir & Erlang/OTP build deps
RUN \
    apk add --no-cache --virtual .erlang-build \
	git dpkg-dev dpkg gcc g++ libc-dev linux-headers make autoconf ncurses-dev openssl-dev unixodbc-dev lksctp-tools-dev tar

WORKDIR /tmp/erlang-build

# Download OTP
RUN \
    curl -sSL "https://github.com/erlang/otp/releases/download/OTP-${ERLANG_VERSION}/otp_src_${ERLANG_VERSION}.tar.gz" | \
    tar --strip-components=1 -xzf -

RUN \
    export ERL_TOP=/tmp/erlang-build \
    && export CPPFLAGS="-D_BSD_SOURCE $CPPFLAGS" \
    && ./configure \
    --build="$(dpkg-architecture --query DEB_HOST_GNU_TYPE)" \
    --prefix=/usr/local \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --without-javac \
    --without-wx \
    --without-debugger \
    --without-observer \
    --without-jinterface \
    --without-et \
    --without-megaco \
    --enable-threads \
    --enable-shared-zlib \
    --enable-ssl=dynamic-ssl-lib \
    && make -j$(getconf _NPROCESSORS_ONLN)

# Install to temporary location
RUN \
    make DESTDIR=/tmp install \
    && cd /tmp && rm -rf /tmp/erlang-build \
    && find /tmp/usr/local -regex '/tmp/usr/local/lib/erlang/\(lib/\|erts-\).*/\(man\|doc\|obj\|c_src\|emacs\|info\|examples\)' | xargs rm -rf \
    && find /tmp/usr/local -name src | xargs -r find | grep -v '\.hrl$' | xargs rm -v || true \
    && find /tmp/usr/local -name src | xargs -r find | xargs rmdir -vp || true \
    # Strip install to reduce size
    && scanelf --nobanner -E ET_EXEC -BF '%F' --recursive /tmp/usr/local | xargs -r strip --strip-all \
    && scanelf --nobanner -E ET_DYN -BF '%F' --recursive /tmp/usr/local | xargs -r strip --strip-unneeded \
    && runDeps="$( \
	scanelf --needed --nobanner --format '%n#p' --recursive /tmp/usr/local \
	| tr ',' '\n' \
	| sort -u \
	| awk 'system("[ -e /tmp/usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    && ln -s /tmp/usr/local/lib/erlang /usr/local/lib/erlang \
    && /tmp/usr/local/bin/erl -eval "beam_lib:strip_release('/tmp/usr/local/lib/erlang/lib')" -s init stop > /dev/null \
    && (/usr/bin/strip /tmp/usr/local/lib/erlang/erts-*/bin/* || true) \
    && apk add --no-cache \
        $runDeps \
        lksctp-tools

WORKDIR /tmp/elixir-build

ENV PATH="/tmp/usr/local/bin:${PATH}"

RUN \
    export ERL_TOP=/tmp/erlang-build \
    && curl -sSL -sSL https://github.com/elixir-lang/elixir/archive/refs/tags/v${ELIXIR_VERSION}.tar.gz | \
	tar -xzf - \
    && cd elixir-${ELIXIR_VERSION} \
    && make && make DESTDIR=/tmp install \
    && mkdir -p ${HEX_HOME} \
    && mix local.hex --force \
    && mix local.rebar --force

## Final image
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}
ARG ALPINE_MIN_VERSION
ARG NODE_VERSION

MAINTAINER Justin Mills <me@jtsmills.com>

ENV LANG=C.UTF-8 \
    HOME=/opt/app/ \
    TERM=xterm \
    ALPINE_MIN_VERSION=${ALPINE_MIN_VERSION}

# Copy Erlang/OTP installation
COPY --from=build /tmp/usr/local /usr/local

WORKDIR ${HOME}

RUN wget https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64-musl.tar.gz
RUN tar -xvf node-v${NODE_VERSION}-linux-x64-musl.tar.gz
RUN rm node-v${NODE_VERSION}-linux-x64-musl.tar.gz

RUN ln -s /var/www/node-v${NODE_VERSION}-linux-x64-musl/bin/node /usr/bin/node
RUN ln -s /var/www/node-v${NODE_VERSION}-linux-x64-musl/bin/npm /usr/bin/npm

RUN \
    adduser -s /bin/sh -u 1001 -G root -h "${HOME}" -S -D default \
    && chown -R 1001:0 "${HOME}" \
    && echo "@main http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MIN_VERSION}/main" >> /etc/apk/repositories \
    && echo "@community http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MIN_VERSION}/community" >> /etc/apk/repositories \
    && echo "@edge http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories \
    && apk --no-cache --update-cache --available upgrade \
    && apk add --no-cache --update-cache \
	bash libstdc++ ca-certificates ncurses openssl pcre unixodbc zlib make g++ wget curl inotify-tools git nodejs npm yarn \
    && update-ca-certificates --fresh

# Add local node module binaries to PATH
ENV PATH=./node_modules/.bin:$PATH

# Ensure latest versions of Hex/Rebar are installed on build
ONBUILD RUN mix do local.hex --force, local.rebar --force

CMD ["bash"]
