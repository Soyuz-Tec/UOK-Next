ARG UOK_REVISION
ARG NODE_IMAGE=docker.io/library/node@sha256:244cc2b53f46f9e876304391d17682b0ddae9ac33491f4857e25e35a36ba7995
ARG ERLANG_IMAGE=docker.io/library/erlang@sha256:ba97a44914a22f12d00a4ce6cf1dcae71f11bd57ab2dedebdbf34f1047cd2a54
ARG RUNTIME_IMAGE=docker.io/library/alpine@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40

FROM ${NODE_IMAGE} AS web_build

WORKDIR /build/web

COPY web/package.json web/package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund

COPY web ./
RUN npm run build -- --outDir /build/uok-ui

FROM ${ERLANG_IMAGE} AS build

ARG ELIXIR_URL=https://github.com/elixir-lang/elixir/releases/download/v1.20.2/elixir-otp-28.zip
ARG ELIXIR_SHA256=5559e5c496ad959bde0bab4dd2b7e92757a0bd45fba6fc58d35584a8337d0ad1
ARG HEX_URL=https://builds.hex.pm/installs/1.20.0/hex-2.5.1-otp-28.ez
ARG HEX_SHA512=690f12f6933088bb32f1d7125485fb13426318c03cfeabcbd3cce55824cddf2a701104b09b7f4cd7092fe7f76d5b669e391a072428ec4526879b36f62820ae5d
ARG REBAR3_URL=https://builds.hex.pm/installs/1.18.4/rebar3-3.25.1-otp-28
ARG REBAR3_SHA512=992fd755b7926fae455e5e07d9d195f4d3e7f181609eed1b9cabfe548624df10d148cd4b59bda40bebb185d3d68f9a9fd68a70b294101c8ad9cf0fadcc683d24

RUN wget -q -T 30 -O /tmp/elixir.zip "${ELIXIR_URL}" && \
    echo "${ELIXIR_SHA256}  /tmp/elixir.zip" | sha256sum -c - && \
    mkdir -p /opt/elixir && \
    unzip -q /tmp/elixir.zip -d /opt/elixir && \
    rm /tmp/elixir.zip

ENV PATH=/opt/elixir/bin:${PATH}
ENV MIX_REBAR3=/opt/rebar3
ENV MIX_ENV=prod

RUN wget -q -T 30 -O /tmp/hex.ez "${HEX_URL}" && \
    echo "${HEX_SHA512}  /tmp/hex.ez" | sha512sum -c - && \
    mix archive.install /tmp/hex.ez --force && \
    rm /tmp/hex.ez && \
    wget -q -T 30 -O /opt/rebar3 "${REBAR3_URL}" && \
    echo "${REBAR3_SHA512}  /opt/rebar3" | sha512sum -c - && \
    chmod 0555 /opt/rebar3

WORKDIR /build

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

ARG UOK_REVISION
RUN printf '%s' "${UOK_REVISION}" | grep -Eq '^[0-9a-f]{40}$'
ENV UOK_BUILD_REVISION=${UOK_REVISION}

COPY config config
COPY lib lib
COPY priv priv
COPY --from=web_build /build/uok-ui priv/static/uok-ui

RUN mix compile --warnings-as-errors && mix release

FROM ${RUNTIME_IMAGE} AS runtime

RUN apk add --no-cache \
      ca-certificates=20260611-r0 \
      libgcc=15.2.0-r2 \
      libstdc++=15.2.0-r2 \
      ncurses-libs=6.5_p20251123-r0 \
      openssl=3.5.8-r0 \
      tzdata=2026c-r0 && \
    addgroup -S -g 10001 uok && \
    adduser -S -D -H -u 10001 -G uok uok && \
    mkdir -p /app && \
    chown 10001:10001 /app

WORKDIR /app

COPY --from=build --chown=10001:10001 /build/_build/prod/rel/uok_next/ ./

ARG UOK_REVISION
LABEL org.opencontainers.image.source="https://github.com/Soyuz-Tec/UOK-Next" \
      org.opencontainers.image.revision="${UOK_REVISION}" \
      org.opencontainers.image.title="UOK Next"

ENV ERL_CRASH_DUMP=/tmp/uok_next_erl_crash.dump
ENV LANG=C.UTF-8

USER 10001:10001

EXPOSE 4000

ENTRYPOINT ["/app/bin/uok_next"]
CMD ["start"]
