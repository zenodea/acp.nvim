.PHONY: test test-unit test-e2e lint format

test: test-unit test-e2e

test-unit:
	nvim --headless -l tests/run.lua

# E2E specs run the real plugin against a fake ACP agent in a dedicated
# process, with XDG dirs pointed at a temp dir so no state leaks in or out.
test-e2e:
	@TMP=$$(mktemp -d); \
	XDG_DATA_HOME=$$TMP XDG_STATE_HOME=$$TMP \
	  nvim --headless -l tests/run.lua 'tests/e2e/*_spec.lua'; \
	STATUS=$$?; rm -rf $$TMP; exit $$STATUS

lint:
	stylua --check lua plugin tests

format:
	stylua lua plugin tests
