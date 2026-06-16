# ISI Medical System — jak działają i komunikują się mikroserwisy

Dokument przygotowany pod prezentację. Skupia się na **architekturze**, **komunikacji
między serwisami** i **gotowych rozwiązaniach**, ze szczególnym naciskiem na dwa
mikroserwisy: **powiadomień** i **dokumentów medycznych**.

---

## 1. Idea: architektura mikroserwisowa

Zamiast jednej wielkiej aplikacji (monolitu) system jest podzielony na **8 niezależnych
serwisów**. Każdy:

- jest osobną aplikacją Django + Django REST Framework,
- ma **własną bazę danych PostgreSQL** (zasada „database per service" — serwisy nie
  współdzielą tabel, nie wchodzą sobie w bazę),
- działa w **osobnym kontenerze Docker**,
- wystawia **REST API** i własną dokumentację Swagger.

Dzięki temu zespół może rozwijać serwisy niezależnie, a każdy da się skalować/wdrażać osobno.

```
                          ┌──────────────────────────┐
                          │   Frontend (React+Vite)  │   :3000
                          └───────────┬──────────────┘
                                      │  REST + JWT (Authorization: Bearer)
        ┌───────────────┬─────────────┼───────────────┬───────────────┐
        ▼               ▼             ▼               ▼               ▼
 auth-identity   appointment     schedule      medical-record   notification
    :8003          :8001          :8008           :8005            :8006
   (login,       (wizyty)    (terminy/sloty)   (dokumenty)     (powiadomienia)
   wydaje JWT)        │             ▲                                  
                      └──REST───────┘   (rezerwacja slotu)
        ▼               ▼
 facility-staff    audit-logging    payment      ← pozostałe serwisy zespołu
    :8004
        │
        ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │  LocalStack  :4566   (emulacja chmury AWS: S3, SQS, SNS, Cognito)│
 └─────────────────────────────────────────────────────────────────┘
```

| Serwis | Port | Odpowiada za | Właściciel |
|---|---|---|---|
| auth-identity-service | 8003 | logowanie, rejestracja, wydawanie tokenów JWT | — |
| appointment-service | 8001 | wizyty (rezerwacja, anulowanie) | Mateusz |
| schedule-service | 8008 | terminy/sloty lekarzy | Mateusz |
| facility-staff-service | 8004 | placówki, lekarze | Andrzej |
| **medical-record-service** | **8005** | **dokumenty medyczne pacjenta** | **Wojtek** |
| **notification-service** | **8006** | **powiadomienia** | **Wojtek** |
| payment-service | — | płatności | Andrzej |
| audit-logging-service | — | audyt zdarzeń | Marcin |

---

## 2. Jak serwisy się komunikują — 3 mechanizmy

### A) Synchronicznie: REST/HTTP (serwis woła serwis)
Najlepszy przykład to **umawianie wizyty**. `appointment-service` musi zarezerwować slot,
który należy do `schedule-service`. Robi to zwykłym żądaniem HTTP:

```
Pacjent klika „Umów wizytę"
        │
        ▼
appointment-service  ──POST /api/v1/slots/{id}/reserve──►  schedule-service
        │                                                     (slot: available → reserved)
        │  ◄──────────── 200 OK {status: reserved} ──────────┘
        ▼
 tworzy wizytę (status: pending_payment)
        │
        └─ jeśli rezerwacja się nie uda → wywołuje /release (zwolnienie slotu)
```

To wzorzec **orkiestracji** — jeden serwis koordynuje operację rozłożoną na dwa serwisy,
z „wycofaniem" (release) w razie błędu. Klient HTTP: biblioteka **`requests`**
(plik `appointment-service/apps/appointments/client.py`).

### B) Bezpieczeństwo: token JWT (uwierzytelnianie bez sesji)
Serwisy **nie współdzielą sesji ani bazy użytkowników**. Tożsamość pacjenta „podróżuje"
w tokenie JWT. Patrz rozdział 4.

### C) Asynchronicznie: kolejki zdarzeń (infrastruktura SQS/SNS)
W LocalStack są utworzone **kolejki SQS** (`app-events`, `notification-jobs`,
`payment-success`, `payment-failed`) i **temat SNS** (`notifications`). To fundament pod
komunikację zdarzeniową (np. „płatność OK" → „wyślij powiadomienie"). Model powiadomień
jest zaprojektowany pod takie zdarzenia (typy: `payment_received`, `appointment_confirmed`…).
W wersji demo powiadomienia wstrzykujemy bezpośrednio skryptem seedującym.

---

## 3. Twoje mikroserwisy — szczegółowo

### 3.1. notification-service (port 8006)

**Po co jest:** przechowuje i udostępnia powiadomienia użytkownika (potwierdzenie wizyty,
przypomnienie, płatność, nowy dokument itd.).

**Modele (tabele w PostgreSQL):**
- `Notification` — pojedyncze powiadomienie: `recipient_id` (UUID pacjenta), `notification_type`,
  `channel` (in_app/email/sms/push), `subject`, `message`, `is_read`, `created_at`.
- `NotificationTemplate` — szablony treści dla typów zdarzeń.
- `NotificationPreference` — preferencje użytkownika (czy chce e-maili, SMS-ów…).

**Najważniejsze endpointy REST:**
| Metoda + ścieżka | Działanie |
|---|---|
| `GET /api/v2/notifications/` | lista powiadomień zalogowanego pacjenta |
| `GET /api/v2/notifications/unread_count/` | liczba nieprzeczytanych (czerwony badge na dzwonku) |
| `PUT /api/v2/notifications/{id}/read/` | oznacz jedno jako przeczytane |
| `PUT /api/v2/notifications/mark_all_as_read/` | oznacz wszystkie |
| `GET/PUT /api/v2/preferences/...` | preferencje powiadomień |

**Jak działa filtrowanie „tylko moje powiadomienia":** widok czyta `sub` z tokenu JWT i
zwraca tylko rekordy, gdzie `recipient_id == sub`. Pacjent nie zobaczy cudzych powiadomień.

```python
# notification-service/api/views.py (uproszczone)
def get_queryset(self):
    return Notification.objects.filter(recipient_id=self.request.user.id)  # user.id = sub z JWT
```

### 3.2. medical-record-service (port 8005)

**Po co jest:** przechowuje **metadane dokumentów medycznych** (wyniki badań, recepty,
skierowania, karty informacyjne) i wskazuje **plik PDF w magazynie S3**.

**Model `MedicalRecord`:** `patient_id` (UUID), `record_type`, `file_name`, `file_url`
(adres pliku w S3), `file_size`, `content_type`, `description`, `created_at`.

**Najważniejsze endpointy:**
| Metoda + ścieżka | Działanie |
|---|---|
| `GET /api/v2/records/` | lista dokumentów pacjenta |
| `GET /api/v2/records/{id}/` | szczegóły jednego dokumentu |
| `GET /api/v2/records/?record_type=recepta` | filtrowanie po typie |

**Integracja z S3 (gotowe rozwiązanie AWS):** sam plik PDF nie leży w bazie — leży w
**S3** (emulowanym przez LocalStack). W bazie jest tylko `file_url`. Przeglądarka pobiera
plik bezpośrednio z S3 pod adresem `http://localhost:4566/medical-records/<plik>.pdf`.
To typowy wzorzec: baza trzyma metadane, obiektowy magazyn (S3) trzyma pliki.

**Filtrowanie per-pacjent / per-rola:** pacjent widzi tylko swoje dokumenty; lekarz/admin
widzą wszystkie (rola czytana z tokenu JWT).

```python
# medical-record-service/api/views.py (uproszczone)
if user.role == 'patient':
    return MedicalRecord.objects.filter(patient_id=str(user.id))   # tylko moje
return MedicalRecord.objects.all()                                  # lekarz/admin: wszystkie
```

---

## 4. Uwierzytelnianie end-to-end (serce integracji)

To najważniejszy fragment do zrozumienia — pokazuje, jak niezależne serwisy „ufają" sobie
nawzajem bez wspólnej bazy użytkowników.

```
1. Frontend:  POST /api/v2/auth/login/  { email, password }
                       │
                       ▼
2. auth-identity-service:
   - sprawdza hasło (PostgreSQL w trybie demo / AWS Cognito w trybie produkcyjnym)
   - generuje token JWT (biblioteka SimpleJWT) podpisany wspólnym SECRET_KEY
   - do tokenu wkłada „claims":   sub = UUID pacjenta,  role = patient,  email
                       │
                       ▼  zwraca id_token
3. Frontend zapisuje token i dołącza go do KAŻDEGO żądania:
                       Authorization: Bearer <token>
                       │
                       ▼
4. notification-service / medical-record-service:
   - klasa JWTStubAuthentication (biblioteka PyJWT) dekoduje token
   - wyciąga sub + role → tworzy „wirtualnego użytkownika" (StubUser)
   - NIE pyta żadnej bazy o użytkownika → uwierzytelnianie BEZSTANOWE (stateless)
                       │
                       ▼
5. Widok filtruje dane po sub (recipient_id / patient_id)
```

**Dlaczego to dobre rozwiązanie integracyjne:**
- **Bezstanowość** — żaden serwis nie musi trzymać sesji ani odpytywać auth-service przy
  każdym żądaniu. Cała tożsamość jest w tokenie.
- **Luźne powiązanie** — serwis powiadomień nie wie nic o tabeli użytkowników; zna tylko
  `sub` (identyfikator) z tokenu.
- **Jeden standard** — JWT to powszechny standard (RFC 7519), te same tokeny działają we
  wszystkich serwisach.

> Uwaga techniczna: w wersji demo serwisy dekodują token **bez weryfikacji podpisu**
> (ufają sieci wewnętrznej). W wersji produkcyjnej weryfikowałyby podpis względem kluczy
> AWS Cognito. Wzorzec (stateless, token-based) jest taki sam.

---

## 5. Gotowe rozwiązania, których użyliśmy (to interesuje prowadzącego)

| Technologia | Rola w systemie |
|---|---|
| **Django + Django REST Framework** | szkielet każdego mikroserwisu i budowa REST API |
| **PostgreSQL** | baza danych — osobna dla każdego serwisu (database-per-service) |
| **Docker + Docker Compose** | konteneryzacja i orkiestracja wszystkich serwisów |
| **JWT** (RFC 7519) | bezstanowe uwierzytelnianie między serwisami |
| **djangorestframework-simplejwt** | wydawanie tokenów JWT w auth-service |
| **PyJWT** | dekodowanie tokenów w serwisach powiadomień i dokumentów |
| **drf-spectacular** | automatyczna dokumentacja OpenAPI / Swagger UI (`/api/docs/`) |
| **django-cors-headers** | obsługa CORS (frontend na innym porcie niż API) |
| **boto3** (AWS SDK dla Pythona) | komunikacja z usługami AWS (S3, SQS, SNS, Cognito) |
| **AWS S3** | magazyn plików PDF dokumentów medycznych |
| **AWS SQS / SNS** | kolejki i temat zdarzeń (infrastruktura komunikacji asynchronicznej) |
| **AWS Cognito** | zarządzanie tożsamością (tryb produkcyjny) |
| **LocalStack** | lokalna emulacja całego AWS — pozwala uruchomić chmurę bez konta AWS |
| **gunicorn** | serwer WSGI uruchamiający aplikacje Django w kontenerach |
| **React + Vite + axios** | frontend (SPA) i klient HTTP do API |

---

## 6. Jak uruchomić cały system

Wymagania: **Docker Desktop** uruchomiony.

```powershell
cd prod-config
.\start_demo.ps1                 # LocalStack + 6 serwisów + dane demo (powiadomienia, dokumenty)
cd frontend-portal ; npm run dev # frontend na http://localhost:3000
```

`start_demo.ps1` po kolei: startuje LocalStack → czeka aż będzie zdrowy → startuje serwisy
→ seeduje dane demo (skrypty `seed_demo.py`).

**Logowanie do aplikacji:** `patient@example.com` / `Patient123!`
(inne konta: `doctor@example.com`, `staff@example.com`, `admin@example.com` — hasła wg wzoru `Rola123!`).

> Tryb logowania: **lokalny** (hasła w PostgreSQL). Przeżywa restart komputera — w przeciwieństwie
> do Cognito w LocalStack, które po restarcie traci użytkowników.

---

## 7. Jak pokazać mikroserwisy OD STRONY BACKENDU

Każdy serwis ma **interaktywną dokumentację Swagger UI** — idealne do pokazania API na żywo:

| Serwis | Swagger UI |
|---|---|
| notification-service | http://localhost:8006/api/docs/ |
| medical-record-service | http://localhost:8005/api/docs/ |
| appointment-service | http://localhost:8001/api/docs/ |
| schedule-service | http://localhost:8008/api/docs/ |
| auth-identity-service | http://localhost:8003/api/docs/ |
| facility-staff-service | http://localhost:8004/api/docs/ |

### Jak wywołać chroniony endpoint (np. w Swaggerze albo w terminalu)

**Krok 1 — zaloguj się i zdobądź token** (PowerShell):
```powershell
$r = Invoke-RestMethod -Uri http://localhost:8003/api/v2/auth/login/ -Method Post `
     -ContentType "application/json" `
     -Body '{"email":"patient@example.com","password":"Patient123!"}'
$token = $r.id_token
$token   # możesz go skopiować do Swaggera (przycisk „Authorize" → Bearer <token>)
```

**Krok 2 — wywołaj endpoint powiadomień:**
```powershell
Invoke-RestMethod -Uri http://localhost:8006/api/v2/notifications/unread_count/ `
  -Headers @{ Authorization = "Bearer $token" }
# => { "unread_count": 4 }

Invoke-RestMethod -Uri http://localhost:8006/api/v2/notifications/ `
  -Headers @{ Authorization = "Bearer $token" }
# => lista 6 powiadomień
```

**Krok 3 — wywołaj endpoint dokumentów:**
```powershell
Invoke-RestMethod -Uri http://localhost:8005/api/v2/records/ `
  -Headers @{ Authorization = "Bearer $token" }
# => lista 4 dokumentów z adresami plików w S3
```

### Dobry trik na prezentację: pokaż token na jwt.io
Wklej `id_token` na https://jwt.io — zobaczysz „claims" (`sub`, `role`, `email`). To wizualnie
tłumaczy, **jak tożsamość pacjenta podróżuje między serwisami**.

### Pokaż plik w S3 (dowód integracji z magazynem obiektowym)
```powershell
docker exec prod-localstack awslocal s3 ls s3://medical-records/
# => blood-test.pdf, prescription.pdf, referral.pdf, discharge.pdf
```
A w przeglądarce: `http://localhost:4566/medical-records/blood-test.pdf` — otworzy się PDF.

---

## 8. Scenariusz prezentacji we frontendzie (ręcznie)

1. **Zaloguj się** jako pacjent → trafiasz na dashboard.
2. **Powiadomienia:** dzwonek w prawym górnym rogu z czerwonym „4". Klik → lista powiadomień
   (różne typy i kanały). Klik **✓** → licznik spada. To `notification-service` filtruje po Twoim `sub`.
3. **Dokumenty medyczne:** „View Medical Records" → lista 4 dokumentów. **Download** → realny
   PDF z **S3**. To `medical-record-service` + magazyn plików.
4. **(dodatkowo) Umów wizytę:** pokazuje komunikację `appointment-service` ↔ `schedule-service`
   (rezerwacja slotu przez REST).

---

## 9. Najczęstsze pytania prowadzącego — gotowe odpowiedzi

- **Jak serwisy się komunikują?** Synchronicznie przez REST/HTTP (np. wizyta→terminy),
  a tożsamość przekazujemy w tokenie JWT. Infrastruktura zdarzeniowa (SQS/SNS) jest gotowa.
- **Jak rozwiązaliście autoryzację między serwisami?** Bezstanowo, tokenem JWT — auth-service
  wydaje token, pozostałe serwisy go dekodują (PyJWT), bez wspólnej bazy sesji.
- **Gdzie trzymacie pliki?** Metadane w PostgreSQL, same pliki PDF w S3 (LocalStack).
- **Czemu osobne bazy?** Wzorzec database-per-service — niezależność i luźne powiązanie serwisów.
- **Co jest „chmurowe"?** S3, SQS, SNS, Cognito — emulowane lokalnie przez LocalStack przez `boto3`.
