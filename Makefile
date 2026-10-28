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
BUILDROOT ?= /home/echan/.cache/uwe5622-build
BUILDSRC ?= $(BUILDROOT)/src/uwe5622-ng

KDIR ?= $(BUILDROOT)/linux-6.18
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-
JOBS ?= 12

# The prepared kernel tree has no Module.symvers, so modpost cannot resolve
# any symbol.  Downgrade those to warnings (symbols are resolved at load time
# against the running kernel).
export KBUILD_MODPOST_WARN := 1

# Switches consumed by the vendored subdirectory Makefiles.
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
	@mkdir -p "$(BUILDSRC)"
	@rsync -a --delete --exclude=.git/ "$(SRC)/" "$(BUILDSRC)/"

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
