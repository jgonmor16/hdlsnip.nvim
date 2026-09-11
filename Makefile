PLENARY := .tests/plenary.nvim
PLENARY_URL := https://github.com/nvim-lua/plenary.nvim
LOG := .tests/last-run.log
GOLDEN := tests/golden

.PHONY: test lint format golden golden-check ghdl vsg demo smoke clean

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
	stylua --check lua tests scripts

## format: apply formatting
format:
	stylua lua tests scripts

## golden: regenerate the committed fixtures
golden:
	@rm -rf $(GOLDEN)
	@nvim --headless --noplugin -u scripts/init.lua -c "luafile scripts/golden.lua"

## golden-check: fail when the committed fixtures are stale
golden-check:
	@rm -rf .tests/golden-new
	@HDLSNIP_GOLDEN_DIR=.tests/golden-new nvim --headless --noplugin \
		-u scripts/init.lua -c "luafile scripts/golden.lua"
	@diff -ru $(GOLDEN) .tests/golden-new > /dev/null 2>&1 || { \
		diff -ru $(GOLDEN) .tests/golden-new || true; \
		echo; \
		echo "Golden fixtures are stale. Run: make golden"; \
		exit 1; \
	}
	@echo "golden fixtures are up to date"

## ghdl: analyse every fixture, each in its own library
##
## Fixtures deliberately reuse design unit names across cases, so each file
## is analysed into a throwaway working directory rather than a shared one.
ghdl:
	@for f in $(GOLDEN)/vhdl/*.vhd; do \
		case "$$f" in *__vhdl93__*) std=93 ;; *) std=08 ;; esac; \
		work=$$(mktemp -d); \
		if ! ghdl -a --std=$$std --workdir=$$work "$$f"; then \
			rm -rf $$work; \
			echo "FAILED to analyse (std=$$std): $$f"; \
			exit 1; \
		fi; \
		rm -rf $$work; \
	done
	@echo "every golden fixture analyses cleanly"

## vsg: style check the fixtures
vsg:
	vsg -c vsg_config.yaml -f $(GOLDEN)/vhdl/*.vhd

## demo: re-record the GIFs (needs vhs, ttyd and ffmpeg)
demo:
	@command -v vhs >/dev/null || { \
		echo "vhs not found: https://github.com/charmbracelet/vhs"; \
		exit 1; \
	}
	@vhs validate demo/*.tape
	@for tape in demo/*.tape; do \
		echo "recording $$tape"; \
		vhs "$$tape" || exit 1; \
	done

## smoke: render every template under several configurations for review
smoke:
	@mkdir -p .tests
	@nvim --headless --noplugin -u scripts/init.lua \
		-c "luafile scripts/smoke.lua"
	@echo "review: .tests/smoke.txt"

## clean: remove test dependencies
clean:
	rm -rf $(PLENARY) $(LOG) .tests/golden-new

$(PLENARY):
	git clone --depth 1 $(PLENARY_URL) $@
