#!/bin/bash
# Phase 3 Verification Script
# Verifies that all Phase 3 migrations completed successfully
#
# Usage: ./scripts/verify_phase3.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

echo -e "${YELLOW}=== Phase 3 Migration Verification ===${NC}"
echo ""

# Check if database container is running
if ! docker compose ps db | grep -q "Up"; then
    echo -e "${RED}ERROR: Database container is not running${NC}"
    exit 1
fi

# Load database credentials
if [ ! -f "./.envs/env.dev" ]; then
    echo -e "${RED}ERROR: ./.envs/env.dev not found${NC}"
    exit 1
fi
source ./.envs/env.dev

echo -e "${YELLOW}1. Checking School table...${NC}"
SCHOOL_COUNT=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM billing_school WHERE id = 1;")

if [ "$(echo $SCHOOL_COUNT | tr -d ' ')" = "1" ]; then
    echo -e "${GREEN}✓ Default school exists${NC}"
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT id, name, subdomain, city, province FROM billing_school WHERE id = 1;"
else
    echo -e "${RED}✗ Default school not found!${NC}"
    ((ERRORS++))
fi
echo ""

echo -e "${YELLOW}2. Checking SchoolSettings...${NC}"
SETTINGS_COUNT=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM billing_schoolsettings WHERE school_id = 1;")

if [ "$(echo $SETTINGS_COUNT | tr -d ' ')" = "1" ]; then
    echo -e "${GREEN}✓ SchoolSettings exists${NC}"
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT school_id, online_teacher_rate, online_student_rate, inperson_student_rate FROM billing_schoolsettings;"
else
    echo -e "${RED}✗ SchoolSettings not found!${NC}"
    ((ERRORS++))
fi
echo ""

echo -e "${YELLOW}3. Checking User.school backfill...${NC}"
ORPHANED_USERS=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM billing_user WHERE school_id IS NULL;")

if [ "$(echo $ORPHANED_USERS | tr -d ' ')" = "0" ]; then
    echo -e "${GREEN}✓ All users have school assigned${NC}"
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT school_id, COUNT(*) as user_count FROM billing_user GROUP BY school_id;"
else
    echo -e "${RED}✗ Found $ORPHANED_USERS users without school!${NC}"
    ((ERRORS++))
fi
echo ""

echo -e "${YELLOW}4. Checking Lesson.school backfill...${NC}"
ORPHANED_LESSONS=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM billing_lesson WHERE school_id IS NULL;")

if [ "$(echo $ORPHANED_LESSONS | tr -d ' ')" = "0" ]; then
    echo -e "${GREEN}✓ All lessons have school assigned${NC}"
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT school_id, COUNT(*) as lesson_count FROM billing_lesson GROUP BY school_id;"
else
    echo -e "${RED}✗ Found $ORPHANED_LESSONS lessons without school!${NC}"
    ((ERRORS++))
fi
echo ""

echo -e "${YELLOW}5. Checking Invoice.school backfill...${NC}"
ORPHANED_INVOICES=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM billing_invoice WHERE school_id IS NULL;")

if [ "$(echo $ORPHANED_INVOICES | tr -d ' ')" = "0" ]; then
    echo -e "${GREEN}✓ All invoices have school assigned${NC}"
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT school_id, invoice_type, COUNT(*) FROM billing_invoice GROUP BY school_id, invoice_type;"
else
    echo -e "${RED}✗ Found $ORPHANED_INVOICES invoices without school!${NC}"
    ((ERRORS++))
fi
echo ""

echo -e "${YELLOW}6. Checking BillableContact.school backfill...${NC}"
ORPHANED_CONTACTS=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM billing_billablecontact WHERE school_id IS NULL;")

if [ "$(echo $ORPHANED_CONTACTS | tr -d ' ')" = "0" ]; then
    echo -e "${GREEN}✓ All billable contacts have school assigned${NC}"
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT school_id, COUNT(*) as contact_count FROM billing_billablecontact GROUP BY school_id;"
else
    echo -e "${RED}✗ Found $ORPHANED_CONTACTS billable contacts without school!${NC}"
    ((ERRORS++))
fi
echo ""

echo -e "${YELLOW}7. Checking InvoiceRecipientEmail.school backfill...${NC}"
ORPHANED_RECIPIENTS=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM billing_invoicerecipientemail WHERE school_id IS NULL;")

if [ "$(echo $ORPHANED_RECIPIENTS | tr -d ' ')" = "0" ]; then
    echo -e "${GREEN}✓ All invoice recipients have school assigned${NC}"
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT school_id, COUNT(*) as recipient_count FROM billing_invoicerecipientemail GROUP BY school_id;"
else
    echo -e "${RED}✗ Found $ORPHANED_RECIPIENTS invoice recipients without school!${NC}"
    ((ERRORS++))
fi
echo ""

echo -e "${YELLOW}8. Checking NOT NULL constraints...${NC}"
NULL_CHECK=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT table_name, column_name, is_nullable
     FROM information_schema.columns
     WHERE column_name = 'school_id'
       AND table_schema = 'public'
       AND table_name IN ('billing_user', 'billing_lesson', 'billing_invoice', 'billing_billablecontact', 'billing_invoicerecipientemail')
     ORDER BY table_name;")

echo "$NULL_CHECK"

NO_COUNT=$(echo "$NULL_CHECK" | grep -c "NO" || true)
if [ "$NO_COUNT" -eq 5 ]; then
    echo -e "${GREEN}✓ All 5 tables have NOT NULL constraint on school_id${NC}"
else
    echo -e "${RED}✗ Some tables missing NOT NULL constraint!${NC}"
    ((ERRORS++))
fi
echo ""

echo -e "${YELLOW}9. Testing constraint enforcement...${NC}"
TEST_RESULT=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
    "INSERT INTO billing_user (email, password, user_type, first_name, last_name)
     VALUES ('test_constraint@test.com', 'fake', 'teacher', 'Test', 'User');" 2>&1 || true)

if echo "$TEST_RESULT" | grep -q "not-null constraint"; then
    echo -e "${GREEN}✓ NOT NULL constraint is enforced (insert without school_id correctly rejected)${NC}"
else
    echo -e "${RED}✗ NOT NULL constraint not enforced!${NC}"
    echo "$TEST_RESULT"
    ((ERRORS++))
fi
echo ""

# Summary
echo -e "${YELLOW}=== Verification Summary ===${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Phase 3 migration successful${NC}"
    echo ""
    echo "Safe to proceed to production deployment"
    exit 0
else
    echo -e "${RED}✗ $ERRORS checks failed!${NC}"
    echo ""
    echo "DO NOT deploy to production until all issues are resolved"
    exit 1
fi
