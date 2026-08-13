#!/bin/bash
# Database Backup Script for Phase 3 Migration
# Run this BEFORE starting Phase 3 migrations
#
# Usage: ./scripts/backup_before_phase3.sh

set -e  # Exit on error

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="./backups"
BACKUP_FILE="$BACKUP_DIR/maple_key_db_phase3_${TIMESTAMP}.sql"

# Colors for output
RED='\033[0:31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Maple Key Music Academy - Phase 3 Backup ===${NC}"
echo "Timestamp: $TIMESTAMP"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Check if database container is running
echo -e "${YELLOW}Checking database container...${NC}"
if ! docker compose ps db | grep -q "Up"; then
    echo -e "${RED}ERROR: Database container is not running${NC}"
    echo "Run: docker compose up -d db"
    exit 1
fi
echo -e "${GREEN}✓ Database container is running${NC}"
echo ""

# Get database connection info from env file
echo -e "${YELLOW}Reading database credentials...${NC}"
if [ ! -f "./.envs/env.dev" ]; then
    echo -e "${RED}ERROR: ./.envs/env.dev not found${NC}"
    exit 1
fi
source ./.envs/env.dev
echo -e "${GREEN}✓ Credentials loaded${NC}"
echo ""

# Create backup
echo -e "${YELLOW}Creating database backup...${NC}"
echo "Output: $BACKUP_FILE"

docker compose exec -T db pg_dump \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    --clean \
    --if-exists \
    --no-owner \
    --no-acl \
    > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}✓ Backup created successfully${NC}"
    echo "  Size: $BACKUP_SIZE"
    echo "  Location: $BACKUP_FILE"
else
    echo -e "${RED}✗ Backup failed${NC}"
    exit 1
fi
echo ""

# Verify backup is not empty
if [ ! -s "$BACKUP_FILE" ]; then
    echo -e "${RED}ERROR: Backup file is empty${NC}"
    exit 1
fi

# Count records before migration
echo -e "${YELLOW}Recording pre-migration record counts...${NC}"
COUNT_FILE="$BACKUP_DIR/record_counts_${TIMESTAMP}.txt"

docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" << EOF > "$COUNT_FILE"
\t
\a
SELECT 'users', COUNT(*) FROM billing_user;
SELECT 'lessons', COUNT(*) FROM billing_lesson;
SELECT 'invoices', COUNT(*) FROM billing_invoice;
SELECT 'billable_contacts', COUNT(*) FROM billing_billablecontact;
SELECT 'invoice_recipients', COUNT(*) FROM billing_invoicerecipientemail;
SELECT 'schools', COUNT(*) FROM billing_school;
SELECT 'school_settings', COUNT(*) FROM billing_schoolsettings;
EOF

echo -e "${GREEN}✓ Record counts saved to: $COUNT_FILE${NC}"
cat "$COUNT_FILE"
echo ""

# Final instructions
echo -e "${GREEN}=== Backup Complete ===${NC}"
echo ""
echo -e "${YELLOW}To restore this backup if needed:${NC}"
echo "  docker compose exec -T db psql -U $POSTGRES_USER -d $POSTGRES_DB < $BACKUP_FILE"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review the backup file exists: ls -lh $BACKUP_FILE"
echo "  2. Proceed with Phase 3 migrations"
echo "  3. Keep this backup until Phase 3 is verified in production"
echo ""
echo -e "${GREEN}You can now safely proceed with migrations${NC}"
