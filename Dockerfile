FROM ponylang/ponyc:release

COPY . /src/main/
WORKDIR /src/main/test
RUN corral run -- ponyc --debug
RUN ./test
CMD ./test
