-- 0001_schema.sql : Początkowy schemat bazy (PostgreSQL 14/15+)
-- Wymagane rozszerzenia: uuid-ossp (uuid_generate_v4) i pgcrypto (gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ===== Typy / ENUM =====
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'batch_status') THEN
    CREATE TYPE batch_status AS ENUM ('available','blocked','consumed','expired');
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inv_count_status') THEN
    CREATE TYPE inv_count_status AS ENUM ('draft','in_progress','counted','posted','canceled');
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'trx_type') THEN
    CREATE TYPE trx_type AS ENUM ('PZ','WZ','RW','ADJUST','TRANSFER');
  END IF;
END$$;

-- ===== Słowniki =====
CREATE TABLE IF NOT EXISTS locations (
  location_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        text NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text
);

CREATE TABLE IF NOT EXISTS products (
  product_id  uuid PRIMARY KEY,
  name        text NOT NULL UNIQUE,
  unit        text NOT NULL CHECK (unit IN ('kg','l','szt')),
  allergen_codes text,                        -- miejsce na kody alergenów (opcjonalnie)
  shelf_life_days int                         -- opcjonalnie: do wyliczeń expiry przy INV
);

-- ===== Magazyn: partie i transakcje =====
CREATE TABLE IF NOT EXISTS batches (
  batch_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id   uuid NOT NULL REFERENCES products(product_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  supplier_id  uuid,                           -- NULL: brak dostawcy (seed/test)
  lot_number   text,
  received_at  timestamptz NOT NULL DEFAULT now(),
  expiry_date  date NOT NULL,
  qty_on_hand  numeric(12,3) NOT NULL CHECK (qty_on_hand >= 0),
  status       batch_status NOT NULL DEFAULT 'available'
);

-- FEFO / szybkie filtry
CREATE INDEX IF NOT EXISTS ix_batches_fefo
  ON batches (product_id, expiry_date ASC, received_at ASC, batch_id ASC);

CREATE INDEX IF NOT EXISTS ix_batches_status_expiry
  ON batches (status, expiry_date);

-- Dziennik ruchów magazynowych (audyt operacji)
CREATE TABLE IF NOT EXISTS inventory_transactions (
  trx_id      uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  batch_id    uuid NOT NULL REFERENCES batches(batch_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  location_id uuid NOT NULL REFERENCES locations(location_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  trx_type    trx_type NOT NULL,                     -- 'PZ','ADJUST', itp.
  qty         numeric(12,3) NOT NULL,                -- dodatnie / ujemne
  reason      text,                                  -- 'seed','inventory_shrinkage','inventory_overage'...
  created_by  text,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

-- ===== Inwentaryzacje (cycle counts) =====
CREATE TABLE IF NOT EXISTS inventory_counts (
  count_id     uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  location_id  uuid NOT NULL REFERENCES locations(location_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  scope        text NOT NULL CHECK (scope IN ('full','category','product','spot')),
  scheduled_at timestamptz NOT NULL DEFAULT now(),
  started_at   timestamptz,
  completed_at timestamptz,
  status       inv_count_status NOT NULL DEFAULT 'draft',
  notes        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text
);

CREATE TABLE IF NOT EXISTS inventory_count_lines (
  count_line_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  count_id      uuid NOT NULL REFERENCES inventory_counts(count_id) ON UPDATE RESTRICT ON DELETE CASCADE,
  product_id    uuid NOT NULL REFERENCES products(product_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  book_qty      numeric(12,3) NOT NULL,
  counted_qty   numeric(12,3) NOT NULL DEFAULT 0 CHECK (counted_qty >= 0),
  variance_qty  numeric(12,3) NOT NULL DEFAULT 0,
  reason        text,
  notes         text,
  UNIQUE(count_id, product_id)
);

-- (opcjonalnie) Jeżeli kiedyś będziesz liczyć per partia — zostawiamy jako możliwość:
CREATE TABLE IF NOT EXISTS inventory_count_batches (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  count_line_id uuid NOT NULL REFERENCES inventory_count_lines(count_line_id) ON UPDATE RESTRICT ON DELETE CASCADE,
  batch_id      uuid NOT NULL REFERENCES batches(batch_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  counted_qty   numeric(12,3) NOT NULL CHECK (counted_qty >= 0),
  UNIQUE(count_line_id, batch_id)
);
