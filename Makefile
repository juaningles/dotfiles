BATS_VERSION ?= v1.11.1
BATS_DIR ?= .tools/bats-core
BATS_BIN := $(BATS_DIR)/bin/bats

.PHONY: bats-install test test-venv clean-bats

bats-install:
	@mkdir -p .tools
	@if [ ! -d "$(BATS_DIR)/.git" ]; then \
		echo "Cloning bats-core $(BATS_VERSION) into $(BATS_DIR)"; \
		git clone --depth 1 --branch "$(BATS_VERSION)" https://github.com/bats-core/bats-core.git "$(BATS_DIR)"; \
	else \
		echo "Updating bats-core to $(BATS_VERSION) in $(BATS_DIR)"; \
		git -C "$(BATS_DIR)" fetch --depth 1 origin "$(BATS_VERSION)"; \
		git -C "$(BATS_DIR)" checkout -q "$(BATS_VERSION)"; \
	fi

test: test-venv

test-venv: bats-install
	@"$(BATS_BIN)" tests/*.bats

clean-bats:
	@rm -rf "$(BATS_DIR)"
