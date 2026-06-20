# ISI Medical System — przewodnik prezentacji (Wojtek: Powiadomienia + Dokumenty)

## Uruchomienie (po starcie Dockera)

```powershell
cd prod-config
.\start_demo.ps1                 # LocalStack + serwisy + dane demo
cd frontend-portal ; npm run dev # frontend na http://localhost:3000
```

Logowanie: **patient@example.com** / **Patient123!**

> Auth działa w trybie lokalnym (bez Cognito) — przeżywa restart komputera.
> Dane (powiadomienia, dokumenty, wizyty) są w bazach PostgreSQL i przeżywają restart.
> Pliki PDF dokumentów żyją w LocalStack S3 (nie przeżywają restartu) — dlatego
> `start_demo.ps1` zawsze odtwarza je przez `seed_demo.py`.

## Scenariusz demo

### 1. Powiadomienia (notification-service, port 8006)
- Po zalogowaniu w prawym górnym rogu **dzwonek z czerwonym „4"** (nieprzeczytane).
- Klik w dzwonek → lista powiadomień (potwierdzenie wizyty, przypomnienie,
  płatność, nowy dokument, odwołanie, powitanie). Różne typy i kanały (in_app/email/sms).
- Klik **✓** przy powiadomieniu → znika z licznika (oznaczone jako przeczytane).
- **„Mark all read"** → licznik spada do zera.
- Architektura: React → `notification-service` (JWT z `sub` pacjenta filtruje powiadomienia).

### 2. Dokumenty medyczne (medical-record-service, port 8005)
- Quick Actions → **„View Medical Records"**.
- Lista 4 dokumentów: wyniki badań, recepta, skierowanie, karta informacyjna.
  Każdy: nazwa, typ, opis, data.
- **„Download"** → pobiera prawdziwy PDF z **LocalStack S3** (integracja z AWS S3).
- Architektura: React → `medical-record-service` → pliki w S3; pacjent widzi tylko swoje rekordy.

### 3. (Dodatkowo) Umawianie wizyty — działa end-to-end
- **Book Appointment** → szukaj lekarza → wybierz datę → wybierz godzinę → Umów.
- Przepływ: `appointment-service` rezerwuje slot w `schedule-service`, tworzy wizytę.
- Nowa wizyta pojawia się w „Upcoming Appointments".

## Porty serwisów
| Serwis | Port |
|---|---|
| auth-identity | 8003 |
| appointment | 8001 |
| schedule | 8008 |
| facility-staff | 8004 |
| medical-record | 8005 |
| notification | 8006 |
| frontend (Vite) | 3000 |
| LocalStack | 4566 |

## Ponowne załadowanie samych danych demo (bez restartu serwisów)
```powershell
docker exec medical-record-service python seed_demo.py
docker exec notification-service python seed_demo.py
```
