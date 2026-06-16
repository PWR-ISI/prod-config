# Co zostało do zrobienia — ISI Medical System

Stan na tydzień przed oddaniem. Zespół 4-osobowy.
Lista tego, czego brakuje, żeby system był kompletny — pogrupowane wg priorytetu.

---

## 🔴 Krytyczne — żeby system był „kompletny"

### 1. Pełny przepływ płatności
Wizyta po umówieniu zostaje w statusie `pending_payment`. Trzeba spiąć:
`appointment-service` → `payment-service` (PayU sandbox) → status `paid`.
Zdarzenie `appointment.paid` jest już obsłużone po stronie powiadomień —
brakuje samej realizacji płatności i przejścia statusu.

### 2. Upload dokumentów medycznych
Obecnie pliki PDF trafiają do S3 tylko przez skrypt seedujący.
Brakuje: endpoint do wgrania pliku (multipart → S3) i powiązania go z wizytą,
żeby lekarz mógł realnie dodać wynik/receptę z poziomu aplikacji.

### 3. Konsumenci zdarzeń jako stałe usługi
Konsument SQS (notification-service) startuje skryptem `start_demo.ps1`
(`docker exec -d ... consume_events`). Docelowo powinien być osobnym
kontenerem w docker-compose z `restart: always` (worker obok web-app).

### 4. Persystencja / automatyczne odtwarzanie infrastruktury AWS
LocalStack gubi S3 / SQS / SNS po restarcie. `start_demo.ps1` to odtwarza,
ale docelowo: persystencja LocalStacka albo idempotentny bootstrap przy starcie.

---

## 🟡 Ważne — jakość i bezpieczeństwo

### 5. Weryfikacja podpisu JWT
Serwisy dekodują token **bez weryfikacji podpisu** (ufają sieci wewnętrznej).
Produkcyjnie: weryfikacja względem klucza (Cognito JWKS / wspólny sekret).

### 6. Presigned URLs zamiast publicznego S3
Bucket `medical-records` jest publiczny — każdy ze znanym linkiem otworzy PDF.
Trzeba: prywatny bucket + presigned URL generowany przez serwis dla właściciela.

### 7. Konfiguracja adresów serwisów
Komunikacja między serwisami idzie przez `host.docker.internal` (działa na dev).
Docelowo: wspólna sieć Dockera / service discovery / adresy z ENV.

### 8. Dashboardy lekarza / personelu / admina
Najbardziej gotowy jest panel pacjenta. Pozostałe role wymagają uzupełnienia
(np. lekarz: lista wizyt, dodanie dokumentu; admin: zarządzanie).

### 9. Harmonogram przypomnień
„Przypomnienie o wizycie" jest teraz seedowane. Potrzebny scheduler
(cron / Celery beat), który tworzy przypomnienia X godzin przed wizytą.

---

## 🟢 Dobre praktyki

10. **Testy automatyczne + CI** (pipeline budujący i testujący serwisy).
11. **Integracja audit-logging-service** — realne logowanie zdarzeń domenowych.
12. **Decyzja: Cognito vs tryb lokalny** — teraz auth działa lokalnie
    (hasła w PostgreSQL), bo Cognito w LocalStack nie przeżywa restartu.

---

## Propozycja podziału na 4 osoby / 1 tydzień
- **Osoba 1:** płatność end-to-end (pkt 1)
- **Osoba 2:** upload dokumentów + presigned URLs (pkt 2, 6)
- **Osoba 3:** konsumenci jako kontenery + scheduler przypomnień (pkt 3, 9)
- **Osoba 4:** dashboardy pozostałych ról + weryfikacja JWT + testy (pkt 5, 8, 10)

---

## Co JUŻ działa (do pokazania na prezentacji)
- Logowanie (tryb lokalny, przeżywa restart)
- Powiadomienia: REST + **event-driven** (umówienie/odwołanie wizyty → automatyczne
  powiadomienie przez SNS→SQS→konsument), licznik nieprzeczytanych, oznaczanie
  jako przeczytane, klikalne rozwijanie treści
- Dokumenty medyczne: lista + pobieranie PDF z S3 (per-pacjent)
- Umawianie i odwoływanie wizyty (komunikacja appointment ↔ schedule po REST)
