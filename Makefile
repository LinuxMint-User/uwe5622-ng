# Standalone (out-of-tree) build for the uwe5622 driver.
#
# Two Kbuild limitations shape this file:
#   1. Kbuild rejects module paths containing spaces.  This project lives in
#      a directory that contains one, so sources are mirrored into BUILDSRC
#      (space-free) before building.
#   2. Kbuild allows only one external module directory per invocation, so
#      every subdirectory is built separately.
#
# Usage:
#   make
#   make KDIR=/path/to/linux-6.18
#   make clean

.DEFAULT_GOAL := all

SRC ?= $(CURDIR)
BUILDROOT ?= $(HOME)/.cache/uwe5622-build
BUILDSRC ?= $(BUILDROOT)/src/uwe5622-ng

KDIR ?= $(BUILDROOT)/linux-6.18-zero3-src
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-
JOBS ?= 12

# The prepared kernel tree has no Module.symvers, so modpost cannot resolve
# any symbol.  Downgrade those to warnings (symbols are resolved at load time
# against the running kernel).
export KBUILD_MODPOST_WARN := 1

# Switches consumed by the vendored subdirectory Makefiles.
# CONFIG_AW_BIND_VERIFY is intentionally left undefined: the bind-verify code in
# unisocwcn/platform/wcn_boot.c depends on vendor crypto patches that mainline
# does not have, so the guarded blocks stay compiled out.
CONFIG_AW_WIFI_DEVICE_UWE5622 := y
CONFIG_TTY_OVERY_SDIO := m
CONFIG_SUNXI_ADDR_MGT := m
export CONFIG_AW_WIFI_DEVICE_UWE5622
export CONFIG_TTY_OVERY_SDIO
export CONFIG_SUNXI_ADDR_MGT

export UNISOC_BSP_INCLUDE := $(BUILDSRC)/unisocwcn/include
export UNISOC_FW_PATH_CONFIG := "/lib/firmware/"

MODDIRS := unisocwcn unisocwifi tty-sdio addr_mgt

sync:
	@if [ "$(abspath $(SRC))" = "$(abspath $(BUILDSRC))" ]; then \
		echo "BUILDSRC == SRC (dkms build), skip rsync"; \
	else \
		mkdir -p "$(BUILDSRC)"; \
		rsync -a --delete --exclude=.git/ "$(SRC)/" "$(BUILDSRC)/"; \
	fi

all: sync
	@set -e; for d in $(MODDIRS); do \
		echo "=== building $$d ==="; \
		$(MAKE) -C $(KDIR) M="$(BUILDSRC)/$$d" ARCH=$(ARCH) \
			CROSS_COMPILE=$(CROSS_COMPILE) -j$(JOBS) modules; \
	done
	@echo "=== artifacts ==="
	@find "$(BUILDSRC)" -name '*.ko' -exec ls -lh {} \;

clean:
	@for d in $(MODDIRS); do \
		$(MAKE) -C $(KDIR) M="$(BUILDSRC)/$$d" ARCH=$(ARCH) \
			CROSS_COMPILE=$(CROSS_COMPILE) clean; \
	done

.PHONY: all clean sync
