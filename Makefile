PLENARY := .tests/plenary.nvim
PLENARY_URL := https://github.com/nvim-lua/plenary.nvim

.PHONY: test lint format clean

## test: run the spec suite headless
test: $(PLENARY)
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests', { minimal_init = 'tests/minimal_init.lua' })"

## lint: check formatting without writing
lint:
	stylua --check lua tests

## format: apply formatting
format:
	stylua lua tests

## clean: remove test dependencies
clean:
	rm -rf $(PLENARY)

$(PLENARY):
	git clone --depth 1 $(PLENARY_URL) $@
