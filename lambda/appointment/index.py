"""
Appointment Lambda — replaces appointment-service ECS.

Handles all appointment CRUD operations via API Gateway proxy events.
Publishes notification events directly to SQS (no SNS fan-out needed).
Idempotency on the notification side is handled by notification-service.
"""
import json
import logging
import os
from datetime import datetime, timezone

import boto3
import psycopg2
import psycopg2.extras

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DB_CONFIG = {
    "host": os.environ["DB_HOST"],
    "port": int(os.environ.get("DB_PORT", 5432)),
    "dbname": os.environ.get("DB_NAME", "coredb"),
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
}
SQS_QUEUE_URL = os.environ["NOTIFICATION_SQS_URL"]
REGION = os.environ.get("AWS_REGION", "us-east-1")
ENDPOINT_URL = os.environ.get("AWS_ENDPOINT_URL")

sqs = boto3.client(
    "sqs",
    region_name=REGION,
    endpoint_url=ENDPOINT_URL if ENDPOINT_URL else None,
)


def get_connection():
    return psycopg2.connect(**DB_CONFIG, cursor_factory=psycopg2.extras.RealDictCursor)


def json_response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def publish_notification_event(event_type: str, payload: dict) -> None:
    """Publish a notification trigger event directly to the notification-service SQS queue."""
    message = json.dumps({"event_type": event_type, "payload": payload})
    sqs.send_message(QueueUrl=SQS_QUEUE_URL, MessageBody=message)
    logger.info("Published %s to notification SQS", event_type)


def lambda_handler(event, context):
    # Support both API Gateway v1 (REST) and v2 (HTTP) event formats.
    ctx = event.get("requestContext", {})
    http_ctx = ctx.get("http", {})
    method = http_ctx.get("method") or event.get("httpMethod", "")
    path = event.get("rawPath") or event.get("path", "")
    path_params = event.get("pathParameters") or {}
    body_raw = event.get("body") or "{}"
    try:
        body = json.loads(body_raw)
    except json.JSONDecodeError:
        body = {}

    appointment_id = path_params.get("id")

    try:
        if method == "GET" and path == "/appointments":
            return list_appointments(event)
        elif method == "POST" and path == "/appointments":
            return create_appointment(body, event)
        elif method == "GET" and path == f"/appointments/{appointment_id}" and appointment_id:
            return get_appointment(appointment_id)
        elif method == "PUT" and path == f"/appointments/{appointment_id}" and appointment_id:
            return update_appointment(appointment_id, body)
        elif method == "POST" and path.endswith("/cancel"):
            return cancel_appointment(appointment_id, body)
        elif method == "POST" and path.endswith("/complete"):
            return complete_appointment(appointment_id)
        elif method == "GET" and path.endswith("/notes"):
            return get_notes(appointment_id)
        elif method == "PUT" and path.endswith("/notes"):
            return update_notes(appointment_id, body)
        elif method == "GET" and path.endswith("/history"):
            return get_history(appointment_id)
        elif method == "GET" and path.endswith("/upcoming"):
            return upcoming_appointments(event)
        else:
            return json_response(404, {"error": "Not found"})
    except Exception:
        logger.exception("Unhandled error in lambda_handler")
        return json_response(500, {"error": "Internal server error"})


def list_appointments(event):
    qp = event.get("queryStringParameters") or {}
    filters = []
    params = []
    for col in ("patient_id", "doctor_id", "status", "appointment_type"):
        if col in qp:
            filters.append(f"{col} = %s")
            params.append(qp[col])
    where = ("WHERE " + " AND ".join(filters)) if filters else ""
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(f"""
            SELECT id, patient_id, doctor_id, appointment_date, appointment_type,
                   status, location, created_at
            FROM appointments {where} ORDER BY appointment_date DESC
        """, params)
        rows = cur.fetchall()
    return json_response(200, [dict(r) for r in rows])


def create_appointment(body, event):
    required = {"patient_id", "doctor_id", "appointment_date", "appointment_type"}
    missing = required - set(body.keys())
    if missing:
        return json_response(400, {"error": f"Missing fields: {missing}"})

    apt_date = body["appointment_date"]
    if datetime.fromisoformat(apt_date.replace("Z", "+00:00")) < datetime.now(timezone.utc):
        return json_response(400, {"error": "appointment_date must be in the future"})

    with get_connection() as conn, conn.cursor() as cur:
        cur.execute("""
            INSERT INTO appointments (patient_id, doctor_id, appointment_date, appointment_type,
                                     description, location, status, reminder_sent, created_at, updated_at)
            VALUES (%s,%s,%s,%s,%s,%s,'scheduled',false,NOW(),NOW()) RETURNING id
        """, (body["patient_id"], body["doctor_id"], apt_date,
              body["appointment_type"], body.get("description", ""), body.get("location", "")))
        new_id = cur.fetchone()["id"]
        cur.execute("""
            INSERT INTO appointment_notes (appointment_id, created_by_id, created_at, updated_at)
            VALUES (%s,%s,NOW(),NOW())
        """, (new_id, body.get("patient_id")))
        conn.commit()

    publish_notification_event("appointment.created", {
        "appointment_id": str(new_id),
        "patient_id": body["patient_id"],
        "doctor_id": body["doctor_id"],
        "scheduled_start": apt_date,
    })
    return json_response(201, {"id": str(new_id)})


def get_appointment(apt_id):
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM appointments WHERE id = %s", (apt_id,))
        row = cur.fetchone()
    if not row:
        return json_response(404, {"error": "Not found"})
    return json_response(200, dict(row))


def update_appointment(apt_id, body):
    allowed = {"appointment_date", "appointment_type", "description", "location", "status"}
    updates = {k: v for k, v in body.items() if k in allowed}
    if not updates:
        return json_response(400, {"error": "No valid fields to update"})
    set_clause = ", ".join(f"{k} = %s" for k in updates)
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(
            f"UPDATE appointments SET {set_clause}, updated_at=NOW() WHERE id = %s RETURNING id",
            list(updates.values()) + [apt_id],
        )
        if not cur.fetchone():
            conn.rollback()
            return json_response(404, {"error": "Not found"})
        conn.commit()
    return json_response(200, {"id": apt_id, **updates})


def cancel_appointment(apt_id, body):
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT status, patient_id, doctor_id, appointment_date FROM appointments WHERE id=%s",
            (apt_id,),
        )
        row = cur.fetchone()
        if not row:
            return json_response(404, {"error": "Not found"})
        if row["status"] == "cancelled":
            return json_response(400, {"error": "Already cancelled"})
        cur.execute("""
            UPDATE appointments SET status='cancelled', updated_at=NOW() WHERE id=%s;
            INSERT INTO appointment_history (appointment_id, previous_status, new_status,
                                            changed_by_id, change_reason, changed_at)
            VALUES (%s, %s, 'cancelled', %s, %s, NOW())
        """, (apt_id, apt_id, row["status"], body.get("changed_by_id", 0), body.get("reason", "")))
        conn.commit()

    publish_notification_event("appointment.cancelled", {
        "appointment_id": apt_id,
        "patient_id": str(row["patient_id"]),
        "doctor_id": str(row["doctor_id"]),
        "scheduled_start": row["appointment_date"].isoformat() if row["appointment_date"] else None,
        "reason": body.get("reason", ""),
    })
    return json_response(200, {"id": apt_id, "status": "cancelled"})


def complete_appointment(apt_id):
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT status, patient_id, doctor_id, appointment_date FROM appointments WHERE id=%s",
            (apt_id,),
        )
        row = cur.fetchone()
        if not row:
            return json_response(404, {"error": "Not found"})
        if row["status"] == "completed":
            return json_response(400, {"error": "Already completed"})
        cur.execute("""
            UPDATE appointments SET status='completed', updated_at=NOW() WHERE id=%s;
            INSERT INTO appointment_history (appointment_id, previous_status, new_status,
                                            changed_by_id, change_reason, changed_at)
            VALUES (%s, %s, 'completed', 0, '', NOW())
        """, (apt_id, apt_id, row["status"]))
        conn.commit()

    publish_notification_event("appointment.completed", {
        "appointment_id": apt_id,
        "patient_id": str(row["patient_id"]),
        "doctor_id": str(row["doctor_id"]),
        "scheduled_start": row["appointment_date"].isoformat() if row["appointment_date"] else None,
    })
    return json_response(200, {"id": apt_id, "status": "completed"})


def get_notes(apt_id):
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM appointment_notes WHERE appointment_id=%s", (apt_id,))
        row = cur.fetchone()
    if not row:
        return json_response(404, {"error": "Not found"})
    return json_response(200, dict(row))


def update_notes(apt_id, body):
    allowed = {"diagnosis", "treatment", "prescriptions", "vital_signs", "follow_up_required", "follow_up_date"}
    updates = {k: v for k, v in body.items() if k in allowed}
    if not updates:
        return json_response(400, {"error": "No valid fields"})
    set_clause = ", ".join(f"{k} = %s" for k in updates)
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(
            f"UPDATE appointment_notes SET {set_clause}, updated_at=NOW() WHERE appointment_id=%s RETURNING id",
            list(updates.values()) + [apt_id],
        )
        if not cur.fetchone():
            conn.rollback()
            return json_response(404, {"error": "Not found"})
        conn.commit()
    return json_response(200, {"appointment_id": apt_id, **updates})


def get_history(apt_id):
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT * FROM appointment_history WHERE appointment_id=%s ORDER BY changed_at DESC",
            (apt_id,),
        )
        rows = cur.fetchall()
    return json_response(200, [dict(r) for r in rows])


def upcoming_appointments(event):
    qp = event.get("queryStringParameters") or {}
    patient_id = qp.get("patient_id")
    with get_connection() as conn, conn.cursor() as cur:
        if patient_id:
            cur.execute("""
                SELECT id, patient_id, doctor_id, appointment_date, appointment_type, status, location
                FROM appointments WHERE status='scheduled' AND appointment_date >= NOW()
                AND patient_id=%s ORDER BY appointment_date LIMIT 10
            """, (patient_id,))
        else:
            cur.execute("""
                SELECT id, patient_id, doctor_id, appointment_date, appointment_type, status, location
                FROM appointments WHERE status='scheduled' AND appointment_date >= NOW()
                ORDER BY appointment_date LIMIT 10
            """)
        rows = cur.fetchall()
    return json_response(200, [dict(r) for r in rows])
