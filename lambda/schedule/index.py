import json
import logging
import os
import uuid
from datetime import datetime, timezone, timedelta

import boto3
import psycopg2
import psycopg2.extras

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DB_CONFIG = {
    "host": os.environ["DB_HOST"],
    "port": int(os.environ.get("DB_PORT", 5432)),
    "dbname": os.environ.get("DB_NAME", "scheduledb"),
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
}
SNS_TOPIC_ARN = os.environ.get("SCHEDULE_SNS_TOPIC_ARN", "")
REGION = os.environ.get("AWS_REGION", "us-east-1")
ENDPOINT_URL = os.environ.get("AWS_ENDPOINT_URL")
RESERVATION_TTL_MINUTES = int(os.environ.get("SLOT_RESERVATION_TTL_MINUTES", "15"))

sns = boto3.client("sns", region_name=REGION, endpoint_url=ENDPOINT_URL or None)


def get_conn():
    return psycopg2.connect(**DB_CONFIG, cursor_factory=psycopg2.extras.RealDictCursor)


CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "*",
}


def resp(status, body):
    return {
        "statusCode": status,
        "headers": CORS_HEADERS,
        "body": json.dumps(body, default=str),
    }


def publish(event_type, payload):
    if not SNS_TOPIC_ARN:
        return
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps({"event_type": event_type, "payload": payload}, default=str),
            Subject=event_type,
        )
    except Exception as e:
        logger.warning("SNS publish failed: %s", e)


def lambda_handler(event, context):
    ctx = event.get("requestContext", {})
    http_ctx = ctx.get("http", {})
    method = http_ctx.get("method") or event.get("httpMethod", "GET")
    path = event.get("rawPath") or event.get("path", "")
    path_params = event.get("pathParameters") or {}
    qs = event.get("queryStringParameters") or {}
    body_raw = event.get("body") or "{}"
    try:
        body = json.loads(body_raw) if body_raw else {}
    except Exception:
        body = {}

    logger.info("%s %s", method, path)

    # Handle CORS preflight
    if method == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    try:
        # ── Slots ──────────────────────────────────────────────────────────
        if path == "/api/v1/slots" and method == "GET":
            return list_slots(qs)
        if path == "/api/v1/slots" and method == "POST":
            return create_slot(body)
        if path.startswith("/api/v1/slots/"):
            slot_id = path_params.get("slot_id") or path.split("/")[4]
            rest = "/".join(path.split("/")[5:])
            if not rest and method == "GET":
                return get_slot(slot_id)
            if rest == "reserve" and method == "POST":
                return reserve_slot(slot_id, body)
            if rest == "release" and method == "POST":
                return release_slot(slot_id)
            if rest == "confirm" and method == "POST":
                return confirm_slot(slot_id)

        # ── Appointments ────────────────────────────────────────────────────
        if path == "/api/v1/appointments" and method == "GET":
            return list_appointments(qs, event)
        if path == "/api/v1/appointments" and method == "POST":
            return create_appointment(body, event)
        if path.startswith("/api/v1/appointments/"):
            apt_id = path_params.get("apt_id") or path.split("/")[4]
            rest = "/".join(path.split("/")[5:])
            if not rest and method == "GET":
                return get_appointment(apt_id)
            if rest == "cancel" and method == "POST":
                return cancel_appointment(apt_id, body)
            if rest == "complete" and method == "POST":
                return complete_appointment(apt_id, body)

        # ── Doctor schedules (stub) ─────────────────────────────────────────
        if path.startswith("/api/v1/doctor-schedules") and method == "GET":
            return list_doctor_schedules(qs)

        # ── Health check ────────────────────────────────────────────────────
        if path in ("/api/v2/health/", "/health"):
            return resp(200, {"status": "ok"})

        return resp(404, {"detail": "Not found."})
    except Exception:
        logger.exception("Unhandled error")
        return resp(500, {"detail": "Internal server error."})


# =============================================================================
# SLOTS
# =============================================================================

def list_slots(qs):
    filters = ["1=1"]
    params = []
    if qs.get("doctor_id"):
        filters.append("doctor_id = %s")
        params.append(qs["doctor_id"])
    if qs.get("from"):
        filters.append("start_time::date >= %s")
        params.append(qs["from"])
    if qs.get("to"):
        filters.append("start_time::date <= %s")
        params.append(qs["to"])
    status_filter = qs.get("status")
    if status_filter == "all":
        pass
    elif status_filter:
        filters.append("status = %s")
        params.append(status_filter)
    else:
        filters.append("status = 'available'")

    where = " AND ".join(filters)
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            f"SELECT * FROM scheduling_slot WHERE {where} ORDER BY start_time LIMIT 500",
            params,
        )
        rows = cur.fetchall()
    return resp(200, [dict(r) for r in rows])


def get_slot(slot_id):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM scheduling_slot WHERE id = %s", (slot_id,))
        row = cur.fetchone()
    if not row:
        return resp(404, {"detail": "Not found."})
    return resp(200, dict(row))


def create_slot(body):
    required = {"doctor_id", "facility_id", "start_time", "end_time"}
    missing = required - set(body)
    if missing:
        return resp(400, {"detail": f"Missing fields: {missing}"})
    new_id = str(uuid.uuid4())
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute(
                """INSERT INTO scheduling_slot
                   (id, doctor_id, facility_id, start_time, end_time, status, created_at, updated_at)
                   VALUES (%s,%s,%s,%s,%s,'available',NOW(),NOW()) RETURNING *""",
                (new_id, body["doctor_id"], body["facility_id"], body["start_time"], body["end_time"]),
            )
            row = cur.fetchone()
            conn.commit()
    except psycopg2.errors.UniqueViolation:
        return resp(409, {"detail": "Slot w tym terminie już istnieje."})
    return resp(201, dict(row))


def reserve_slot(slot_id, body):
    appointment_id = body.get("appointment_id")
    if not appointment_id:
        return resp(400, {"detail": "appointment_id required."})
    ttl = body.get("ttl_minutes", RESERVATION_TTL_MINUTES)
    expires = (datetime.now(timezone.utc) + timedelta(minutes=int(ttl))).isoformat()
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM scheduling_slot WHERE id = %s FOR UPDATE", (slot_id,))
        slot = cur.fetchone()
        if not slot:
            return resp(404, {"detail": "Not found."})
        if slot["status"] != "available":
            return resp(409, {"detail": f"Slot is {slot['status']}."})
        cur.execute(
            """UPDATE scheduling_slot SET status='reserved', appointment_id=%s,
               reservation_expires_at=%s, updated_at=NOW() WHERE id=%s RETURNING *""",
            (appointment_id, expires, slot_id),
        )
        row = cur.fetchone()
        conn.commit()
    publish("slot.reserved", dict(row))
    return resp(200, dict(row))


def release_slot(slot_id):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM scheduling_slot WHERE id = %s FOR UPDATE", (slot_id,))
        slot = cur.fetchone()
        if not slot:
            return resp(404, {"detail": "Not found."})
        if slot["status"] == "available":
            return resp(200, dict(slot))
        cur.execute(
            """UPDATE scheduling_slot SET status='available', appointment_id=NULL,
               reservation_expires_at=NULL, updated_at=NOW() WHERE id=%s RETURNING *""",
            (slot_id,),
        )
        row = cur.fetchone()
        conn.commit()
    publish("slot.released", dict(row))
    return resp(200, dict(row))


def confirm_slot(slot_id):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM scheduling_slot WHERE id = %s FOR UPDATE", (slot_id,))
        slot = cur.fetchone()
        if not slot:
            return resp(404, {"detail": "Not found."})
        if slot["status"] == "confirmed":
            return resp(200, dict(slot))
        if slot["status"] != "reserved":
            return resp(409, {"detail": f"Cannot confirm from status {slot['status']}."})
        cur.execute(
            """UPDATE scheduling_slot SET status='confirmed', reservation_expires_at=NULL,
               updated_at=NOW() WHERE id=%s RETURNING *""",
            (slot_id,),
        )
        row = cur.fetchone()
        conn.commit()
    publish("slot.confirmed", dict(row))
    return resp(200, dict(row))


# =============================================================================
# APPOINTMENTS
# =============================================================================

def _slot_row(cur, slot_id):
    cur.execute("SELECT * FROM scheduling_slot WHERE id = %s", (slot_id,))
    return cur.fetchone()


def list_appointments(qs, event):
    filters = ["1=1"]
    params = []
    role = (event.get("headers") or {}).get("x-user-role", "")
    user_id = (event.get("headers") or {}).get("x-user-id", "")

    if role == "doctor" and user_id:
        filters.append("s.doctor_id = %s")
        params.append(user_id)
    elif role in ("admin", "receptionist", "staff"):
        if qs.get("doctor_id"):
            filters.append("s.doctor_id = %s")
            params.append(qs["doctor_id"])
        if qs.get("patient_id"):
            filters.append("a.patient_id = %s")
            params.append(qs["patient_id"])
    else:
        if user_id:
            filters.append("a.patient_id = %s")
            params.append(user_id)

    where = " AND ".join(filters)
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            f"""SELECT a.*, s.start_time AS appointment_date, s.doctor_id, s.end_time
                FROM scheduling_appointment a
                JOIN scheduling_slot s ON a.slot_id = s.id
                WHERE {where}
                ORDER BY s.start_time DESC LIMIT 200""",
            params,
        )
        rows = cur.fetchall()
    return resp(200, [dict(r) for r in rows])


def create_appointment(body, event):
    slot_id = body.get("slot_id")
    if not slot_id:
        return resp(400, {"detail": "slot_id required."})
    patient_id = body.get("patient_id") or (event.get("headers") or {}).get("x-user-id", "")
    notes = body.get("notes", "")
    new_id = str(uuid.uuid4())

    with get_conn() as conn, conn.cursor() as cur:
        slot = _slot_row(cur, slot_id)
        if not slot:
            return resp(404, {"detail": "Slot not found."})
        if slot["status"] != "available":
            return resp(409, {"detail": f"Slot unavailable: {slot['status']}."})

        # Create appointment
        cur.execute(
            """INSERT INTO scheduling_appointment
               (id, patient_id, slot_id, status, notes, visit_summary,
                cancellation_reason, payment_order_id, created_at, updated_at)
               VALUES (%s,%s,%s,'scheduled',%s,'','','',NOW(),NOW()) RETURNING *""",
            (new_id, patient_id, slot_id, notes),
        )
        apt = cur.fetchone()

        # Reserve slot
        expires = (datetime.now(timezone.utc) + timedelta(minutes=RESERVATION_TTL_MINUTES)).isoformat()
        cur.execute(
            """UPDATE scheduling_slot SET status='reserved', appointment_id=%s,
               reservation_expires_at=%s, updated_at=NOW() WHERE id=%s""",
            (new_id, expires, slot_id),
        )
        # Confirm immediately (no payment flow in Lambda simplified version)
        cur.execute(
            """UPDATE scheduling_slot SET status='confirmed', reservation_expires_at=NULL,
               updated_at=NOW() WHERE id=%s""",
            (slot_id,),
        )
        cur.execute(
            "UPDATE scheduling_appointment SET status='scheduled' WHERE id=%s RETURNING *",
            (new_id,),
        )
        apt = cur.fetchone()
        conn.commit()

    publish("appointment.created", {
        "appointment_id": new_id,
        "patient_id": str(patient_id),
        "slot_id": slot_id,
        "doctor_id": str(slot["doctor_id"]),
        "scheduled_start": slot["start_time"].isoformat() if slot["start_time"] else None,
        "status": "scheduled",
    })
    return resp(201, dict(apt))


def get_appointment(apt_id):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT a.*, s.start_time AS appointment_date, s.doctor_id, s.end_time
               FROM scheduling_appointment a
               JOIN scheduling_slot s ON a.slot_id = s.id
               WHERE a.id = %s""",
            (apt_id,),
        )
        row = cur.fetchone()
    if not row:
        return resp(404, {"detail": "Not found."})
    return resp(200, dict(row))


def cancel_appointment(apt_id, body):
    reason = body.get("reason", "")
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT a.*, s.doctor_id, s.start_time FROM scheduling_appointment a JOIN scheduling_slot s ON a.slot_id=s.id WHERE a.id=%s",
            (apt_id,),
        )
        apt = cur.fetchone()
        if not apt:
            return resp(404, {"detail": "Not found."})
        if apt["status"] == "cancelled":
            return resp(400, {"detail": "Already cancelled."})

        cur.execute(
            """UPDATE scheduling_appointment SET status='cancelled', cancellation_reason=%s,
               cancelled_at=NOW(), updated_at=NOW() WHERE id=%s RETURNING *""",
            (reason, apt_id),
        )
        updated = cur.fetchone()
        # Release slot
        cur.execute(
            """UPDATE scheduling_slot SET status='available', appointment_id=NULL,
               reservation_expires_at=NULL, updated_at=NOW() WHERE id=%s""",
            (apt["slot_id"],),
        )
        conn.commit()

    publish("appointment.cancelled", {
        "appointment_id": apt_id,
        "patient_id": str(apt["patient_id"]),
        "doctor_id": str(apt["doctor_id"]),
        "scheduled_start": apt["start_time"].isoformat() if apt["start_time"] else None,
        "reason": reason,
        "status": "cancelled",
    })
    return resp(200, dict(updated))


def complete_appointment(apt_id, body):
    summary = body.get("visit_summary", "")
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT a.*, s.doctor_id, s.start_time FROM scheduling_appointment a JOIN scheduling_slot s ON a.slot_id=s.id WHERE a.id=%s",
            (apt_id,),
        )
        apt = cur.fetchone()
        if not apt:
            return resp(404, {"detail": "Not found."})
        cur.execute(
            """UPDATE scheduling_appointment SET status='completed', visit_summary=%s,
               completed_at=NOW(), updated_at=NOW() WHERE id=%s RETURNING *""",
            (summary, apt_id),
        )
        updated = cur.fetchone()
        conn.commit()

    publish("appointment.completed", {
        "appointment_id": apt_id,
        "patient_id": str(apt["patient_id"]),
        "doctor_id": str(apt["doctor_id"]),
        "scheduled_start": apt["start_time"].isoformat() if apt["start_time"] else None,
        "status": "completed",
    })
    return resp(200, dict(updated))


def list_doctor_schedules(qs):
    with get_conn() as conn, conn.cursor() as cur:
        if qs.get("doctor_id"):
            cur.execute("SELECT * FROM scheduling_doctorschedule WHERE doctor_id=%s ORDER BY weekday, start_time", (qs["doctor_id"],))
        else:
            cur.execute("SELECT * FROM scheduling_doctorschedule ORDER BY doctor_id, weekday, start_time LIMIT 200")
        rows = cur.fetchall()
    return resp(200, [dict(r) for r in rows])
