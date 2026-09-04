PLENARY := .tests/plenary.nvim
PLENARY_URL := https://github.com/nvim-lua/plenary.nvim
LOG := .tests/last-run.log

.PHONY: test lint format clean

## test: run the spec suite headless
test: $(PLENARY)
	@mkdir -p $(dir $(LOG))
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests', \
		  { minimal_init = 'tests/minimal_init.lua', sequential = true })" \
		> $(LOG) 2>&1; \
	status=$$?; \
	cat $(LOG); \
	files=$$(ls tests/*_spec.lua | wc -l); \
	started=$$(grep -c 'Testing:' $(LOG) || true); \
	missing=$$(awk '/Testing:/{if(f)print f; f=$$NF} /Success: /{f=""} \
		END{if(f)print f}' $(LOG)); \
	if [ "$$started" -ne "$$files" ] || [ -n "$$missing" ]; then \
		echo; \
		echo "FAIL: $$files spec files on disk, $$started started."; \
		for f in $$missing; do \
			echo "  no results from $$f -- it died on load. Run it alone:"; \
			echo "    nvim --headless --noplugin -u tests/minimal_init.lua \\"; \
			echo "      -c \"lua require('plenary.busted').run('$$f')\""; \
		done; \
		exit 1; \
	fi; \
	exit $$status

## lint: check formatting without writing
lint:
	stylua --check lua tests

## format: apply formatting
format:
	stylua lua tests

## clean: remove test dependencies
clean:
	rm -rf $(PLENARY) $(LOG)

$(PLENARY):
	git clone --depth 1 $(PLENARY_URL) $@
