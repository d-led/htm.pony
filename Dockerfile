# The compiler comes from ponyup rather than from ponylang/ponyc on Docker Hub:
# those images stop at 0.58.0, and the stb_image decoder is a C source beside a
# package, which ponyc only compiles from 0.65.0 on. Keep this version in step
# with PONYC_VERSION in .github/workflows/ci.yml.
ARG PONYC_VERSION=0.77.2

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      lsb-release \
 && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/ponylang/ponyup/latest-release/ponyup-init.sh | sh
ENV PATH="/root/.local/share/ponyup/bin:${PATH}"

ARG PONYC_VERSION
RUN ponyup update ponyc release "$PONYC_VERSION" && ponyup update corral release

COPY . /src/main/
WORKDIR /src/main/test
RUN corral run -- ponyc --debug
RUN ./test
CMD ["./test"]
