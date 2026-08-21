GO ?= /opt/homebrew/bin/go

.PHONY: build test plugin clean

build:
	mkdir -p bin
	$(GO) build -o bin/bob-wordbook-helper ./cmd/bob-wordbook-helper

test:
	$(GO) test ./...

plugin:
	bash release.sh

clean:
	@test ! -e bin || /usr/bin/trash bin
	@test ! -e dist || /usr/bin/trash dist
