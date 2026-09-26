APP=rsync
BUILD_DIR=.build/debug

CLT_DIR = /Library/Developer/CommandLineTools
SWIFT_PM_DIR = $(CLT_DIR)/usr/lib/swift/pm
SWB_FW_DIR = $(SWIFT_PM_DIR)/SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/Frameworks
SWIFT_FW_PATH = $(SWIFT_PM_DIR):$(SWB_FW_DIR):$(SWIFT_PM_DIR)/llbuild

SWIFT_BIN := $(shell [ -x "$(CLT_DIR)/usr/bin/swift" ] && echo "$(CLT_DIR)/usr/bin/swift" || echo "swift")
SWIFT = DYLD_FRAMEWORK_PATH=$(SWIFT_FW_PATH) $(SWIFT_BIN)

.PHONY: main dev-main run bundle open clean

main: dev-main

dev-main:
	$(SWIFT) build --disable-sandbox

bundle: dev-main
	@bash Scripts/bundle.sh

run:
	@pkill -x $(APP) 2>/dev/null || true
	@pkill -x GoogleDriveSync 2>/dev/null || true
	@sleep 0.5
	$(SWIFT) build --disable-sandbox
	@echo "Launching $(APP)..."
	@nohup ./$(BUILD_DIR)/$(APP) >/dev/null 2>&1 &
	@sleep 0.5
	@pgrep -x $(APP) >/dev/null && echo "$(APP) is running!" || echo "Warning: failed to launch $(APP)"

open:
	@pkill -x $(APP) 2>/dev/null || true
	@pkill -x GoogleDriveSync 2>/dev/null || true
	@sleep 0.5
	@nohup ./$(BUILD_DIR)/$(APP) >/dev/null 2>&1 &

clean:
	@$(SWIFT) package reset
	@rm -rf .build
