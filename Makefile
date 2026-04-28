# Auto-detect repo root (where this Makefile lives)
DOTFILES_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
HOME_DIR := $(HOME)
CONFIG_HOME := $(if $(XDG_CONFIG_HOME),$(XDG_CONFIG_HOME),$(HOME_DIR)/.config)
BIN_DIR := $(HOME)/.local/bin

# Things we don't want to symlink
EXCLUDES := .git .gitignore README.md Makefile

.PHONY: install font

install:
	@echo "Dotfiles dir: $(DOTFILES_DIR)"
	@echo "Installing to: $(HOME_DIR)"
	@echo "Config home: $(CONFIG_HOME)"
	@echo

	@echo "Ensuring bin directory exists..."
	mkdir -p $(BIN_DIR)

	@echo "Processing root dotfiles..."
	@for file in $(DOTFILES_DIR)/.*; do \
		name=$$(basename $$file); \
		skip=false; \
		for ex in $(EXCLUDES); do \
			[ "$$name" = "$$ex" ] && skip=true; \
		done; \
		[ "$$name" = "." ] || [ "$$name" = ".." ] && skip=true; \
		[ "$$name" = ".bin" ] && skip=true; \
		[ "$$name" = ".crucial" ] && skip=true; \
		[ "$$name" = "wezterm.lua" ] && skip=true; \
		if [ "$$skip" = false ]; then \
			target="$(HOME_DIR)/$$name"; \
			echo "Linking $$name → $$target"; \
			rm -rf "$$target"; \
			ln -s "$$file" "$$target"; \
		fi \
	done

	@echo
	@echo "Installing WezTerm config..."
	@rm -f "$(CONFIG_HOME)/wezterm/wezterm.lua"
	@ln -s "$(DOTFILES_DIR)/wezterm.lua" "$(CONFIG_HOME)/wezterm/wezterm.lua"
	@echo "Linked wezterm.lua → $(CONFIG_HOME)/wezterm/wezterm.lua"
	
	@echo
	@echo "Processing .bin scripts..."
	@for file in $(DOTFILES_DIR)/.bin/*; do \
		name=$$(basename $$file); \
		target="$(BIN_DIR)/$${name%.sh}"; \
		echo "Linking $$name → $$target"; \
		rm -f "$$target"; \
		ln -s "$$file" "$$target"; \
		chmod +x "$$file"; \
	done

	@echo
	@echo "Processing .custom directory..."
	@if [ -d "$(DOTFILES_DIR)/.custom" ]; then \
		target="$(HOME_DIR)/.custom"; \
		echo "Linking .custom → $$target"; \
		rm -rf "$$target"; \
		ln -s "$(DOTFILES_DIR)/.custom" "$$target"; \
	fi

	@echo
	@echo "Install complete."

font:
	@echo "Installing fonts..."
	./install_fonts.sh
