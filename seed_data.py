#!/usr/bin/env python3
"""
ISI Medical System - Seed script (dane testowe)
------------------------------------------------
Uruchom: python seed_data.py
Wymagania: pip install requests
Serwisy muszą być uruchomione (docker compose up)

Co tworzy:
  - 4 konta demo (patient, doctor, staff, admin)
  - 1 placówkę medyczną
  - 1 lekarza powiązanego z kontem doctor@example.com
  - Sloty na 2 tygodnie (pon-pt, 9:00-17:00, co 30 min)
"""

import base64
import json
import uuid
from datetime import date, datetime, timedelta

try:
    import requests
except ImportError:
    print("Brak pakietu 'requests'. Zainstaluj: pip install requests")
    raise SystemExit(1)

# ── Adresy serwisów ──────────────────────────────────────────────────────────
AUTH_URL     = "http://localhost:8003/api/v2"
FACILITY_URL = "http://localhost:8004/api/v2"
SCHEDULE_URL = "http://localhost:8008/api/v1"

# ── Demo użytkownicy ─────────────────────────────────────────────────────────
DEMO_USERS = [
    {
        "email": "patient@example.com",
        "password": "Patient123!",
        "password_confirm": "Patient123!",
        "first_name": "Jan",
        "last_name": "Pacjent",
        "role": "patient",
    },
    {
        "email": "doctor@example.com",
        "password": "Doctor123!",
        "password_confirm": "Doctor123!",
        "first_name": "Anna",
        "last_name": "Lekarz",
        "role": "doctor",
    },
    {
        "email": "staff@example.com",
        "password": "Staff123!",
        "password_confirm": "Staff123!",
        "first_name": "Maria",
        "last_name": "Rejestracja",
        "role": "staff",
    },
    {
        "email": "admin@example.com",
        "password": "Admin123!",
        "password_confirm": "Admin123!",
        "first_name": "Piotr",
        "last_name": "Admin",
        "role": "admin",
    },
]


# ── Helpers ──────────────────────────────────────────────────────────────────

def decode_jwt_payload(token: str) -> dict:
    part = token.split(".")[1]
    part += "=" * (4 - len(part) % 4)
    return json.loads(base64.b64decode(part))


def auth_header(token_data: dict) -> dict:
    return {"Authorization": f"Bearer {token_data['id_token']}"}


def ok(msg):  print(f"  [OK] {msg}")
def skip(msg): print(f"  [--] {msg}")
def err(msg):  print(f"  [!!] {msg}")


# ── Kroki seeda ──────────────────────────────────────────────────────────────

def step1_register_users():
    """Rejestruje demo użytkowników, pomija już istniejące."""
    print("\n[1/4] Rejestracja użytkowników demo")
    tokens = {}
    user_uuids = {}

    for u in DEMO_USERS:
        r = requests.post(f"{AUTH_URL}/auth/register/", json=u, timeout=10)

        if r.status_code == 201:
            data = r.json()
            ok(f"{u['role']:8} | {u['email']}")
        elif r.status_code == 400 and "already" in r.json().get("error", "").lower():
            # Użytkownik istnieje — zaloguj się
            r2 = requests.post(
                f"{AUTH_URL}/auth/login/",
                json={"email": u["email"], "password": u["password"]},
                timeout=10,
            )
            if r2.status_code == 200:
                data = r2.json()
                skip(f"{u['role']:8} | {u['email']} (już istnieje)")
            else:
                err(f"{u['email']} — login failed: {r2.text[:80]}")
                continue
        else:
            err(f"{u['email']} — {r.status_code} {r.text[:80]}")
            continue

        tokens[u["role"]] = data
        payload = decode_jwt_payload(data["id_token"])
        user_uuids[u["role"]] = payload.get("sub")

    return tokens, user_uuids


def step2_create_facility(headers: dict) -> int | None:
    """Tworzy placówkę, zwraca jej id."""
    print("\n[2/4] Placówka medyczna")

    r = requests.get(f"{FACILITY_URL}/facilities/", headers=headers, timeout=10)
    if r.status_code == 200:
        existing = r.json()
        if isinstance(existing, dict):
            existing = existing.get("results", [])
        if existing:
            skip(f"Placówka już istnieje: {existing[0]['name']} (id={existing[0]['id']})")
            return existing[0]["id"]

    payload = {
        "name": "Centrum Medyczne ISI",
        "address": "ul. Wybrzeże Wyspiańskiego 27",
        "city": "Wrocław",
        "phone": "+48 71 320 00 00",
        "email": "kontakt@cm-isi.pl",
    }
    r = requests.post(f"{FACILITY_URL}/facilities/", json=payload, headers=headers, timeout=10)
    if r.status_code == 201:
        fid = r.json()["id"]
        ok(f"Placówka utworzona: Centrum Medyczne ISI (id={fid})")
        return fid
    else:
        err(f"Nie udało się stworzyć placówki: {r.status_code} {r.text[:100]}")
        return None


def step3_create_doctor(doctor_uuid: str, facility_id: int, headers: dict):
    """Dodaje lekarza do facility-staff-service."""
    print("\n[3/4] Lekarz")

    r = requests.get(f"{FACILITY_URL}/doctors/", headers=headers, timeout=10)
    if r.status_code == 200:
        existing = r.json()
        if isinstance(existing, dict):
            existing = existing.get("results", [])
        ids = [str(d.get("user_id")) for d in existing]
        if doctor_uuid in ids:
            skip(f"Lekarz już istnieje (user_id={doctor_uuid[:12]}...)")
            return

    payload = {
        "user_id": doctor_uuid,
        "email": "doctor@example.com",
        "first_name": "Anna",
        "last_name": "Lekarz",
        "specialization": "Lekarz pierwszego kontaktu",
        "license_number": "PWR/2024/001",
        "facility_id": facility_id,   # JSON Schema requires facility_id (not facility)
    }
    r = requests.post(f"{FACILITY_URL}/doctors/", json=payload, headers=headers, timeout=10)
    if r.status_code == 201:
        ok(f"Lekarz dodany: Dr. Anna Lekarz (user_id={doctor_uuid[:12]}...)")
    else:
        err(f"Nie udało się dodać lekarza: {r.status_code} {r.text[:100]}")


def step4_create_slots(doctor_uuid: str, facility_id: int, headers: dict):
    """Tworzy sloty dla lekarza na 2 tygodnie (pon-pt, 9:00–17:00, co 30 min)."""
    print("\n[4/4] Sloty wizyt (2 tygodnie)")

    # facility-staff-service ma int PK, schedule-service czeka UUID — tworzymy deterministyczny UUID
    facility_uuid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"isi-facility-{facility_id}"))

    today = date.today()
    created = 0
    skipped = 0

    for day_offset in range(14):
        slot_date = today + timedelta(days=day_offset)
        if slot_date.weekday() >= 5:   # sobota=5, niedziela=6
            continue

        hour, minute = 9, 0
        while (hour, minute) < (17, 0):
            start = datetime(slot_date.year, slot_date.month, slot_date.day, hour, minute)
            end   = start + timedelta(minutes=30)

            r = requests.post(
                f"{SCHEDULE_URL}/slots",
                json={
                    "doctor_id":   doctor_uuid,
                    "facility_id": facility_uuid,
                    "start_time":  start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "end_time":    end.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "status":      "available",
                },
                headers=headers,
                timeout=10,
            )

            if r.status_code in (200, 201):
                created += 1
            elif r.status_code in (400, 500) and (
                "unique" in r.text.lower() or "already" in r.text.lower()
                or "duplicate" in r.text.lower() or r.status_code == 500
            ):
                skipped += 1  # already exists (service returns 500 on IntegrityError)
            else:
                err(f"Slot {start}: {r.status_code} {r.text[:60]}")

            minute += 30
            if minute >= 60:
                minute = 0
                hour += 1

    if created:
        ok(f"Slotów stworzono: {created}")
    if skipped:
        skip(f"Slotów już istniało: {skipped}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("=" * 52)
    print("   ISI Medical System — Seed Data")
    print("=" * 52)

    # 1. Użytkownicy
    tokens, user_uuids = step1_register_users()

    if not tokens:
        err("Brak tokenów — sprawdź czy auth-service działa na :8003")
        return

    # Preferuj admin token, fallback na cokolwiek dostępne
    admin_token = tokens.get("admin") or tokens.get("staff") or next(iter(tokens.values()))
    doctor_uuid = user_uuids.get("doctor")
    headers_admin  = auth_header(admin_token)
    headers_doctor = auth_header(tokens.get("doctor", admin_token))

    # 2. Placówka
    facility_id = step2_create_facility(headers_admin)
    if not facility_id:
        err("Brak facility_id — przerywam (facility-service może nie odpowiadać na :8004)")
        facility_id = 1

    # 3. Lekarz
    if doctor_uuid:
        step3_create_doctor(doctor_uuid, facility_id, headers_admin)
    else:
        err("Brak doctor_uuid — pominięto tworzenie lekarza")

    # 4. Sloty
    if doctor_uuid:
        step4_create_slots(doctor_uuid, facility_id, headers_doctor)
    else:
        err("Brak doctor_uuid — pominięto tworzenie slotów")

    # Podsumowanie
    print("\n" + "=" * 52)
    print("   Demo credentials")
    print("=" * 52)
    for u in DEMO_USERS:
        print(f"  {u['role']:8} | {u['email']:30} | {u['password']}")
    print()
    print("  Frontend:  http://localhost:3000")
    print("  Auth API:  http://localhost:8003/api/docs/")
    print("  Appt API:  http://localhost:8001/api/docs/")
    print("  Schedule:  http://localhost:8008/api/docs/")
    print("  Facility:  http://localhost:8004/api/docs/")
    print()


if __name__ == "__main__":
    main()
