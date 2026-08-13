#!/bin/bash
# Rollback Phase 3 Migrations
# Use this if Phase 3 migration fails and you need to revert
#
# Usage: ./scripts/rollback_phase3.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}=== Phase 3 Migration Rollback ===${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will reverse all Phase 3 migrations${NC}"
echo "This will:"
echo "  - Remove school FK constraints"
echo "  - Clear school_id from all tables"
echo "  - Remove School and SchoolSettings data"
echo ""
read -p "Are you sure you want to rollback? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Rollback cancelled"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting rollback...${NC}"

# Check current migration state
echo "Current migration state:"
docker compose exec api python manage.py showmigrations billing | tail -15

echo ""
read -p "Proceed with rollback to migration 0025? (yes/no): " PROCEED

if [ "$PROCEED" != "yes" ]; then
    echo "Rollback cancelled"
    exit 0
fi

echo ""
echo -e "${YELLOW}Rolling back migrations...${NC}"

# Rollback to 0025 (before Phase 3)
docker compose exec api python manage.py migrate billing 0025

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Migrations rolled back to 0025${NC}"
else
    echo -e "${RED}✗ Rollback failed!${NC}"
    echo "You may need to restore from backup"
    exit 1
fi

echo ""
echo -e "${YELLOW}Verifying rollback...${NC}"

# Load database credentials
if [ ! -f "./.envs/env.dev" ]; then
    echo -e "${RED}ERROR: ./.envs/env.dev not found${NC}"
    exit 1
fi
source ./.envs/env.dev

# Check that school_id columns are gone
SCHOOL_COLUMNS=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*)
     FROM information_schema.columns
     WHERE column_name = 'school_id'
       AND table_schema = 'public'
       AND table_name IN ('billing_user', 'billing_lesson', 'billing_invoice', 'billing_billablecontact', 'billing_invoicerecipientemail');")

COLUMN_COUNT=$(echo $SCHOOL_COLUMNS | tr -d ' ')

if [ "$COLUMN_COUNT" = "0" ]; then
    echo -e "${GREEN}✓ All school_id columns removed${NC}"
else
    echo -e "${YELLOW}⚠ Some school_id columns still exist (historical tables only is OK)${NC}"
fi

# Check that School table is gone
SCHOOL_TABLE=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*)
     FROM information_schema.tables
     WHERE table_name = 'billing_school';")

if [ "$(echo $SCHOOL_TABLE | tr -d ' ')" = "0" ]; then
    echo -e "${GREEN}✓ School table removed${NC}"
else
    echo -e "${YELLOW}⚠ School table still exists${NC}"
fi

echo ""
echo -e "${GREEN}=== Rollback Complete ===${NC}"
echo ""
echo "Database has been rolled back to state before Phase 3"
echo "You can now:"
echo "  1. Fix the issues that caused migration to fail"
echo "  2. Re-run Phase 3 migrations"
echo ""
echo -e "${YELLOW}Or restore from backup if needed:${NC}"
echo "  cat ./backups/maple_key_db_phase3_*.sql | docker compose exec -T db psql -U $POSTGRES_USER -d $POSTGRES_DB"
