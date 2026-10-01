.PHONY: build test lint fmt fmt-check coverage snapshot slither

build:
	forge build

test:
	forge test -vvv

lint:
	yarn run lint

fmt:
	forge fmt

fmt-check:
	forge fmt --check

coverage:
	forge coverage $(COVERAGE_ARGS)

snapshot:
	forge snapshot $(SNAPSHOT_ARGS)

slither:
	slither .
