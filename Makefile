GO ?= go
GOFMT ?= gofmt
NODE ?= node
PYTHON ?= python3
VERSION ?= $(shell $(PYTHON) -c 'import json; print(json.load(open("src/info.json"))["version"])')
LDFLAGS := -s -w -X main.version=$(VERSION)

.PHONY: build check clean install plugin test test-plugin uninstall validate

build:
	mkdir -p bin
	$(GO) build -trimpath -ldflags "$(LDFLAGS)" -o bin/bob-wordbook-helper ./cmd/bob-wordbook-helper

test:
	$(GO) test -race ./...

test-plugin:
	$(NODE) --test tests/plugin_test.js

validate:
	$(PYTHON) scripts/validate_plugin.py

check: validate test test-plugin
	@test -z "$$($(GOFMT) -l cmd/bob-wordbook-helper/*.go)" || (echo "Go files need formatting" >&2; exit 1)
	$(GO) vet ./...
	$(NODE) --check src/main.js
	bash -n release.sh scripts/install.sh scripts/uninstall.sh

plugin: validate
	bash release.sh

install: build
	bash scripts/install.sh bin/bob-wordbook-helper

uninstall:
	bash scripts/uninstall.sh

clean:
	@test ! -e bin || /usr/bin/trash bin
	@test ! -e dist || /usr/bin/trash dist
