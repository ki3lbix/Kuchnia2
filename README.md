# Catering Backend – Starter (GitHub CI-ready)

**Stack:** .NET 8, PostgreSQL 15.  
Zawiera: schemat DB (DDL), seed, minimalne API, logikę domenową (BOM/FEFO/ROP), testy Unit/Integration/E2E oraz workflow GitHub Actions.

## Szybki start (lokalnie)
```bash
docker compose up -d
pwsh ./scripts/psql-apply.ps1 -Conn "Host=localhost;Username=postgres;Password=postgres;Database=catering" -Sql ./db/catering_schema_postgres.sql
pwsh ./scripts/psql-apply.ps1 -Conn "Host=localhost;Username=postgres;Password=postgres;Database=catering" -Sql ./db/catering_seed_postgres.sql
dotnet build
dotnet test
