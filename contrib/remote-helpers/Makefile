TESTS := $(wildcard test-*.t)
SCRIPTS := $(wildcard git-remote-*.py)
LINKS := $(addprefix ../../,$(patsubst %.py,%,$(SCRIPTS)))

export T := $(addprefix $(CURDIR)/,$(TESTS))
export MAKE := $(MAKE) -e
export TEST_LINT := test-lint-executable test-lint-shell-syntax
export TEST_DIRECTORY := $(CURDIR)/../../t

export SCRIPT_PYTHON := $(addprefix $(CURDIR)/,$(SCRIPTS))

all: $(SCRIPTS)
	$(MAKE) -C ../.. build-python-script

install:
	$(MAKE) -C ../.. install-python-script

links: all $(LINKS)

test: links
	$(MAKE) -C ../../t $@

$(LINKS):
	ln -sf contrib/remote-helpers/$(notdir $@) ../..

$(TESTS): links
	$(MAKE) -C ../../t $(CURDIR)/$@

.PHONY: all install test links $(TESTS)
