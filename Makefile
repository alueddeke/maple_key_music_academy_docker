up:
	@echo "============================================================"
	@echo "  MapleKey DEV environment"
	@echo "  Frontend: http://localhost:5173   Backend: http://localhost:8000"
	@echo "  No demo data yet? Run: make seed   (test users @maplekeytest.com)"
	@echo "============================================================"
	docker compose up --build

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

.PHONY: up seed monitor down test
