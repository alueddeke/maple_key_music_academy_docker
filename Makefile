up:
	@echo "============================================================"
	@echo "  MapleKey DEV environment"
	@echo "  Frontend: http://localhost:5173   Backend: http://localhost:8000"
	@echo "  First boot auto-seeds demo data. Sign in:"
	@echo "    e2e.manager@maplekeytest.com / testpass123  (management)"
	@echo "  Empty database instead: make up-empty"
	@echo "============================================================"
	docker compose up --build

# Boot WITHOUT demo data (audit item 16's --no-data flag).
up-empty:
	DEV_SEED=off docker compose up --build

# Factory reset: wipe ALL dev data (DB, monitoring volumes) and boot fresh —
# the next `up` re-runs first-boot auto-seed. This is how you see the
# new-developer experience; a reclone alone won't (named volumes survive it).
reset:
	docker compose down -v
	$(MAKE) up

# Seed realistic dev data (teachers, students, draft batches). Only wipes
# @maplekeytest.com accounts — safe to re-run. Anyone cloning this repo can
# sign in and reach their assigned feature without hand-creating users.
seed:
	docker compose exec backend python manage.py seed_realistic

# Local monitoring never notifies: alerting off (prod keeps the compose default
# of on). To exercise alert rules locally, run the compose command by hand
# with GRAFANA_ALERTING_ENABLED=true and no GRAFANA_SMTP_* exported.
monitor:
	GRAFANA_ALERTING_ENABLED=false docker compose --profile monitoring up --build

down:
	docker compose --profile monitoring down

test:
	docker compose --profile testing up --build --abort-on-container-exit api-tests

.PHONY: up up-empty reset seed monitor down test
