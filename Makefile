up:
	docker compose up --build

monitor:
	docker compose --profile monitoring up --build

down:
	docker compose --profile monitoring down

test:
	docker compose --profile testing up --build --abort-on-container-exit api-tests

.PHONY: up monitor down test
