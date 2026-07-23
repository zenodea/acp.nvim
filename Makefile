.PHONY: test lint format

test:
	nvim --headless -l tests/run.lua

lint:
	stylua --check lua plugin tests

format:
	stylua lua plugin tests
