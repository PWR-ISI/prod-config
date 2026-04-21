"""Utility to run individual docker-compose files from IDE (callable functions).

Usage from IDE: open this file and run e.g. `up_appointment()` to bring up that service.
Also usable as CLI: `python docker_compose_runner.py all` or `python docker_compose_runner.py appointment`
"""
from pathlib import Path
import subprocess
import sys
from typing import List

ROOT = Path(__file__).resolve().parent


def run_compose(files: List[str]):
    cmd: List[str] = ["docker", "compose"]
    for f in files:
        cmd += ["-f", str(ROOT / f)]
    cmd += ["up", "-d", "--build"]
    print("Running:", " ".join(cmd))
    subprocess.run(cmd, check=True)


def up_api_gateway():
    run_compose(["api-gateway/docker-compose.yml"])


def up_appointment():
    run_compose(["appointment-service/docker-compose.yml"])


def up_audit_logging():
    run_compose(["audit-logging-service/docker-compose.yml"])


def up_auth_identity():
    run_compose(["auth-identity-service/docker-compose.yml"])


def up_facility_staff():
    run_compose(["facility-staff-service/docker-compose.yml"])


def up_medical_record():
    run_compose(["medical-record-service/docker-compose.yml"])


def up_notification():
    run_compose(["notification-service/docker-compose.yml"])


def up_payment():
    run_compose(["payment-service/docker-compose.yml"])


def up_schedule():
    run_compose(["schedule-service/docker-compose.yml"])


def up_frontend():
    run_compose(["frontend-portal/docker-compose.yml"])


def up_all():
    files = [
        "api-gateway/docker-compose.yml",
        "appointment-service/docker-compose.yml",
        "audit-logging-service/docker-compose.yml",
        "auth-identity-service/docker-compose.yml",
        "facility-staff-service/docker-compose.yml",
        "medical-record-service/docker-compose.yml",
        "notification-service/docker-compose.yml",
        "payment-service/docker-compose.yml",
        "schedule-service/docker-compose.yml",
        "frontend-portal/docker-compose.yml",
    ]
    run_compose(files)


def main(argv: List[str]):
    if not argv:
        argv = ["all"]
    name = argv[0]
    mapping = {
        "all": up_all,
        "api-gateway": up_api_gateway,
        "appointment": up_appointment,
        "audit-logging": up_audit_logging,
        "auth-identity": up_auth_identity,
        "facility-staff": up_facility_staff,
        "medical-record": up_medical_record,
        "notification": up_notification,
        "payment": up_payment,
        "schedule": up_schedule,
        "frontend": up_frontend,
    }
    func = mapping.get(name)
    if not func:
        print(f"Unknown target: {name}")
        return 2
    try:
        func()
    except subprocess.CalledProcessError as e:
        print("Command failed:", e)
        return e.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
