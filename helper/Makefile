.PHONY: build install uninstall clean

BINARY = shanbay-cookie-helper
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
	@echo "Running initial extraction..."
	@$(INSTALL_PATH)
	@echo ""
	@echo "Installing LaunchAgent..."
	@$(INSTALL_PATH) install
	@echo ""
	@echo "=== Installation complete ==="

uninstall:
	@echo "Uninstalling..."
	@-$(INSTALL_PATH) uninstall 2>/dev/null || true
	@rm -f $(INSTALL_PATH)
	@rm -f $(BINARY)
	@rm -f /tmp/shanbay-cookie-helper.log /tmp/shanbay-cookie-helper.err
	@echo "Uninstall complete."

clean:
	rm -f $(BINARY)
