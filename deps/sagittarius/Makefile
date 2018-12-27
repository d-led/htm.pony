build/sagittarius: build sagittarius/*.pony
	ponyc sagittarius -o build --debug

build:
	mkdir build

test: build/sagittarius
	build/sagittarius

clean:
	rm -rf build

.PHONY: clean test
