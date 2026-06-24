import psycopg2

conn = psycopg2.connect(
    host="localhost.localstack.cloud", port=4512,
    dbname="scheduledb", user="isiAdmin", password="IsiProd123!#2025"
)
cur = conn.cursor()

cur.execute("""
CREATE TABLE IF NOT EXISTS scheduling_slot (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID NOT NULL,
    facility_id UUID NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'available',
    appointment_id UUID,
    reservation_expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT uniq_doctor_start_time UNIQUE (doctor_id, start_time)
);
""")

cur.execute("""
CREATE TABLE IF NOT EXISTS scheduling_appointment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL,
    slot_id UUID NOT NULL REFERENCES scheduling_slot(id),
    status VARCHAR(16) NOT NULL DEFAULT 'scheduled',
    notes TEXT DEFAULT '',
    visit_summary TEXT DEFAULT '',
    cancellation_reason TEXT DEFAULT '',
    payment_order_id VARCHAR(64) DEFAULT '',
    completed_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
""")

cur.execute("""
CREATE TABLE IF NOT EXISTS scheduling_doctorschedule (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID NOT NULL,
    facility_id UUID NOT NULL,
    weekday INTEGER NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    slot_duration_minutes INTEGER NOT NULL DEFAULT 30,
    valid_from DATE NOT NULL,
    valid_until DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
""")

conn.commit()

cur.execute("SELECT tablename FROM pg_tables WHERE schemaname='public'")
print("Tables:", [r[0] for r in cur.fetchall()])

# Seed some slots for demo
import uuid
from datetime import datetime, timedelta, timezone

doctor_id = "00000000-0000-0000-0000-000000000001"
facility_id = "00000000-0000-0000-0000-000000000000"
base = datetime.now(timezone.utc).replace(hour=9, minute=0, second=0, microsecond=0)

slots_created = 0
for day_offset in range(0, 7):
    day = base + timedelta(days=day_offset)
    if day.weekday() >= 5:
        continue
    for slot_hour in range(9, 17):
        for slot_min in [0, 30]:
            start = day.replace(hour=slot_hour, minute=slot_min)
            end = start + timedelta(minutes=30)
            slot_id = str(uuid.uuid4())
            cur.execute(
                """INSERT INTO scheduling_slot
                   (id, doctor_id, facility_id, start_time, end_time, status, created_at, updated_at)
                   VALUES (%s,%s,%s,%s,%s,'available',NOW(),NOW())
                   ON CONFLICT (doctor_id, start_time) DO NOTHING""",
                (slot_id, doctor_id, facility_id, start.isoformat(), end.isoformat())
            )
            slots_created += 1

conn.commit()
cur.execute("SELECT COUNT(*) FROM scheduling_slot")
print(f"Slots in DB: {cur.fetchone()[0]}")
conn.close()
print("Done!")
