FROM ponylang/ponyc:release

COPY . /src/main/
WORKDIR /src/main/test
RUN ponyc && ./test
