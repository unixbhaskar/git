TESTS := $(wildcard test-*.t)
SCRIPTS := $(wildcard git-remote-*.py)

export T := $(addprefix $(CURDIR)/,$(TESTS))
export MAKE := $(MAKE) -e
export PATH := $(CURDIR):$(PATH)
export TEST_LINT := test-lint-executable test-lint-shell-syntax
export TEST_DIRECTORY := $(CURDIR)/../../t

export SCRIPT_PYTHON := $(addprefix $(CURDIR)/,$(SCRIPTS))

all: $(SCRIPTS)
	$(MAKE) -C ../.. build-python-script

install:
	$(MAKE) -C ../.. install-python-script

test: all
	$(MAKE) -C ../../t $@

$(TESTS): all
	$(MAKE) -C ../../t $(CURDIR)/$@

.PHONY: all install test $(TESTS)
