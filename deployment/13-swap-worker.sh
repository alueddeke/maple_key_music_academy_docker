#!/usr/bin/env bash
# 13 — swap the two background processes that share the backend image:
# the send-run worker and the scheduler (MAP-154). Both run only after the
# backend passed health; neither failure rolls the deploy back.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
require_deploy_env

# ===== SWAP SEND-RUN WORKER =====
# Same image, different entrypoint: drains InvoiceSendRuns (bulk invoice
# sends) off the request workers. Swapped only after the backend passed
# health (a failed deploy leaves the old worker running the old image —
# consistent with the rolled-back backend). --stop-timeout 60 lets it finish
# the in-flight invoice on SIGTERM; startup recovery re-queues anything a
# hard kill left behind.
docker stop --time 60 maple-key-worker 2>/dev/null || true
docker rm maple-key-worker 2>/dev/null || true

docker run -d \
  --name maple-key-worker \
  --restart unless-stopped \
  --stop-timeout 60 \
  --network maple-key-network \
  "${BACKEND_ENV[@]}" \
  -v /var/log/maple-key:/var/log/maple-key \
  "$IMAGE" \
  python3 manage.py process_invoice_send_runs

sleep 5
if [ "$(docker inspect maple-key-worker --format='{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "⚠️  Send-run worker failed to start — bulk invoice sends will queue without draining."
  docker logs maple-key-worker --tail 30 2>/dev/null || true
  echo "Backend is healthy; NOT rolling back for a worker failure. Fix the worker manually."
else
  echo "✅ Send-run worker running"
fi

# ===== SWAP SCHEDULER =====
# Same image, different entrypoint (MAP-154): retries stuck webhook events
# every 15 min, reconciles Helcim payments daily, and exports the
# unresolved-events gauge on 9103 for the 'scheduler' Prometheus job. Same
# env as the worker; same no-rollback policy.
docker stop maple-key-scheduler 2>/dev/null || true
docker rm maple-key-scheduler 2>/dev/null || true

docker run -d \
  --name maple-key-scheduler \
  --restart unless-stopped \
  --network maple-key-network \
  "${BACKEND_ENV[@]}" \
  -e SCHEDULER_METRICS_PORT=9103 \
  -v /var/log/maple-key:/var/log/maple-key \
  "$IMAGE" \
  python3 manage.py run_scheduler

sleep 5
if [ "$(docker inspect maple-key-scheduler --format='{{.State.Running}}' 2>/dev/null)" != "true" ]; then
  echo "⚠️  Scheduler failed to start — stuck webhook events will not be retried automatically."
  docker logs maple-key-scheduler --tail 30 2>/dev/null || true
  echo "Backend is healthy; NOT rolling back for a scheduler failure. Fix the scheduler manually."
else
  echo "✅ Scheduler running"
fi
