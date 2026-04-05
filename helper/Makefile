.PHONY: build install uninstall clean

BINARY = bob-wordbook-helper
INSTALL_PATH = /usr/local/bin/$(BINARY)

build:
	@echo "Building $(BINARY)..."
	@cd Sources && swiftc -o ../$(BINARY) ShanbayCookieHelper/main.swift \
		-lsqlite3 \
		-framework Security \
		-framework Foundation \
		-framework CryptoKit
	@echo "Build complete: ./$(BINARY)"

install: build
	@echo "Installing to $(INSTALL_PATH)..."
	@cp $(BINARY) $(INSTALL_PATH)
	@chmod +x $(INSTALL_PATH)
	@echo ""
	@echo "Running initial token extraction..."
	@-$(INSTALL_PATH) extract
	@echo ""
	@echo "Installing LaunchAgent (every 1 minute)..."
	@$(INSTALL_PATH) install
	@echo ""
	@echo "=== Installation complete ==="
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run '$(INSTALL_PATH) init' to configure your Markdown wordbook path"
	@echo "  2. Install the Bob plugin (.bobplugin file)"
	@echo "  3. Make sure you're logged in to shanbay.com in your browser"

uninstall:
	@echo "Uninstalling..."
	@-$(INSTALL_PATH) uninstall 2>/dev/null || true
	@rm -f $(INSTALL_PATH)
	@rm -f $(BINARY)
	@rm -f /tmp/bob-wordbook-helper.log /tmp/bob-wordbook-helper.err
	@rm -rf ~/.config/bob-wordbook
	@echo "Uninstall complete."

clean:
	rm -f $(BINARY)
