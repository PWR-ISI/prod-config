from datetime import datetime, timedelta, time, date
from django.utils import timezone
from apps.scheduling.models import Slot, SlotStatus

doctor_id = "00000000-0000-0000-0000-000000000001"
facility_id = "00000000-0000-0000-0000-000000000000"
d = date(2026, 6, 9)
end = date(2026, 6, 30)
created = 0
while d <= end:
    if d.weekday() < 5:  # weekdays only
        t = timezone.make_aware(datetime.combine(d, time(9, 0)))
        eod = timezone.make_aware(datetime.combine(d, time(17, 0)))
        while t < eod:
            se = t + timedelta(minutes=30)
            if not Slot.objects.filter(doctor_id=doctor_id, start_time=t).exists():
                Slot.objects.create(
                    doctor_id=doctor_id, facility_id=facility_id,
                    start_time=t, end_time=se, status=SlotStatus.AVAILABLE,
                )
                created += 1
            t = se
    d = d + timedelta(days=1)

rng = Slot.objects.filter(
    doctor_id=doctor_id,
    start_time__date__gte=date(2026, 6, 9),
    start_time__date__lte=date(2026, 6, 30),
)
days = sorted(set(s.start_time.date().isoformat() for s in rng))
print("CREATED=%d RANGE_TOTAL=%d DISTINCT_DAYS=%d" % (created, rng.count(), len(days)))
print("FIRST_DAY=%s LAST_DAY=%s" % (days[0] if days else "-", days[-1] if days else "-"))
