# Mobeehive – aplikacja

Aplikacja Flutter (Android, później iOS) do prowadzenia pasieki. Backend: wtyczka WordPress z repozytorium `mobeehive-wp` (API pod `https://mobeehive.pl/wp-json/mobeehive/v1`).

- Dane zapisywane lokalnie (SQLite) i synchronizowane z serwerem – aplikacja działa bez zasięgu.
- Każdy POST do API wysyła treść JSON (filtr hostingu odrzuca pusty POST kodem 406).
- Pola tak/nie wysyłamy jako 1/0.

Budowanie: push na `main` → GitHub Actions „Zbuduj aplikację” → plik APK w artefaktach przebiegu.
