APP_VERSION := $(shell grep '^version:' mobile/pubspec.yaml | head -1 | awk '{print $$2}')
NEW_TAG := v$(APP_VERSION)

# CI injects this; override for local builds: make android SERVER_URL=http://192.168.1.5:3000
SERVER_URL ?= http://localhost:3000

# ── Build locally ──────────────────────────────────────────────

.PHONY: android ios clean

android:
	cd mobile && flutter build apk --debug \
		--dart-define=SERVER_URL=$(SERVER_URL)

ios:
	cd mobile && flutter build ios --debug --no-codesign \
		--dart-define=SERVER_URL=$(SERVER_URL)

clean:
	cd mobile && flutter clean
	cd render-server && cargo clean

# ── Version & release ──────────────────────────────────────────

.PHONY: bump tag push

bump:
	@echo "Current: $(APP_VERSION)"
	@echo "Increment major? (y/n)"; read ans; \
	if [ "$$ans" = "y" ]; then \
		Major=$$(echo $(APP_VERSION) | cut -d. -f1); \
		New="$$((Major+1)).0.0"; \
		sed -i '' "s/^version:.*/version: $$New+1/" mobile/pubspec.yaml; \
		echo "Bumped to $$New"; \
	else \
		Minor=$$(echo $(APP_VERSION) | cut -d. -f2); \
		New="$(shell echo $(APP_VERSION) | cut -d. -f1).$$((Minor+1)).0"; \
		sed -i '' "s/^version:.*/version: $$New+1/" mobile/pubspec.yaml; \
		echo "Bumped to $$New"; \
	fi

tag:
	git add mobile/pubspec.yaml
	git commit -m "release: $(APP_VERSION)"
	git tag $(NEW_TAG)
	git push origin $(NEW_TAG)

release: tag
	@echo "Pushed tag $(NEW_TAG) — GitHub Actions will build and attach artifacts."

# ── Server ─────────────────────────────────────────────────────

.PHONY: server lint

server:
	cd render-server && cargo run

lint:
	cd mobile && flutter analyze
	cd render-server && cargo check

# ── All in one ─────────────────────────────────────────────────

.PHONY: ci

ci: lint
	@echo "Lint passed. Run 'make release' to tag and deploy."
