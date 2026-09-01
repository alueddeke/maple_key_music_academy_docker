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

# Seed realistic dev data (teachers, students, draft batches). Only wipes
# @maplekeytest.com accounts — safe to re-run. Anyone cloning this repo can
# sign in and reach their assigned feature without hand-creating users.
seed:
	docker compose exec backend python manage.py seed_realistic

monitor:
	docker compose --profile monitoring up --build

down:
	docker compose --profile monitoring down

test:
	docker compose --profile testing up --build --abort-on-container-exit api-tests

.PHONY: up up-empty seed monitor down test
