APP := Loci.app

AGENT := br.dutra.loci
PLIST := $(HOME)/Library/LaunchAgents/$(AGENT).plist

.PHONY: build app run start stop install uninstall fmt clean

build:
	swift build -c release

# Two spaces, and the rest of the house style. Configured in .swift-format.
fmt:
	swift format -i -r -p Sources Package.swift

# macOS grants the right to post keystrokes per binary path, so the bundle is
# built in place and stays there. Moving it asks for accessibility again.
app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp .build/release/Loci $(APP)/Contents/MacOS/Loci
	# Ad hoc signature. Unsigned, the permission is re-asked on every build.
	codesign --force --sign - --identifier br.dutra.loci $(APP)

# Tied to this terminal, so the log is visible and Ctrl+C stops it. This is the
# one to use while working on Loci.
run: app
	./$(APP)/Contents/MacOS/Loci

# Detached, for actually using it. Closing the terminal does not stop it.
start: app
	open $(APP)

stop:
	pkill -f "$(APP)/Contents/MacOS/Loci" || true

# Starts Loci at login, which is the only way it is useful: a hotkey that only
# exists after I remember to launch something is a hotkey I will stop pressing.
# No KeepAlive on purpose, so Quit in the menu means quit.
install: app
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '	<key>Label</key><string>$(AGENT)</string>' \
	  '	<key>ProgramArguments</key>' \
	  '	<array><string>$(CURDIR)/$(APP)/Contents/MacOS/Loci</string></array>' \
	  '	<key>RunAtLoad</key><true/>' \
	  '	<key>ProcessType</key><string>Interactive</string>' \
	  '</dict>' \
	  '</plist>' > $(PLIST)
	launchctl bootout gui/$(shell id -u)/$(AGENT) 2>/dev/null || true
	launchctl bootstrap gui/$(shell id -u) $(PLIST)
	@echo "Loci starts at login. Undo with: make uninstall"

uninstall:
	launchctl bootout gui/$(shell id -u)/$(AGENT) 2>/dev/null || true
	rm -f $(PLIST)

clean:
	rm -rf .build $(APP)
