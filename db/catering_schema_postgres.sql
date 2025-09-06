-- Schemat bazy PostgreSQL 15+ dla systemu cateringowego
-- Generowany w kroku S3 (Inżynier DB)

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================
-- Klienci i lokalizacje
-- =====================
CREATE TABLE clients (
  client_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  type text NOT NULL CHECK (type IN ('school','kindergarten','company')),
  tax_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE locations (
  location_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_id uuid NOT NULL REFERENCES clients(client_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  name text NOT NULL,
  address text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ================
-- Produkty i dostawcy
-- ================
CREATE TABLE suppliers (
  supplier_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  contact text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE products (
  product_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  unit text NOT NULL CHECK (unit IN ('kg','l','piece','portion')),
  allergen text,
  shelf_life_days integer CHECK (shelf_life_days >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ================
-- Receptury i składniki
-- ================
CREATE TABLE recipes (
  recipe_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  meal_type text NOT NULL CHECK (meal_type IN ('breakfast','lunch','dinner','snack')),
  diet_type text NOT NULL CHECK (diet_type IN ('std','gf','vege','vegan')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE recipe_items (
  recipe_item_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  recipe_id uuid NOT NULL REFERENCES recipes(recipe_id) ON UPDATE RESTRICT ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(product_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  qty_per_portion numeric(12,3) NOT NULL CHECK (qty_per_portion > 0),
  loss_pct numeric(5,2) NOT NULL DEFAULT 0 CHECK (loss_pct >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ===========
-- Menu i zamówienia
-- ===========
CREATE TABLE menus (
  menu_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  location_id uuid NOT NULL REFERENCES locations(location_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  date date NOT NULL,
  recipe_id uuid NOT NULL REFERENCES recipes(recipe_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(location_id,date,recipe_id)
);

CREATE TABLE orders (
  order_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  location_id uuid NOT NULL REFERENCES locations(location_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  order_date date NOT NULL,
  cutoff_time time,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE order_items (
  order_item_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid NOT NULL REFERENCES orders(order_id) ON UPDATE RESTRICT ON DELETE CASCADE,
  menu_id uuid NOT NULL REFERENCES menus(menu_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  portions integer NOT NULL CHECK (portions >= 0)
);

-- ===========
-- Partie i magazyn
-- ===========
CREATE TABLE batches (
  batch_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id uuid NOT NULL REFERENCES products(product_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  supplier_id uuid REFERENCES suppliers(supplier_id) ON UPDATE RESTRICT ON DELETE SET NULL,
  lot_number text,
  received_at timestamptz NOT NULL,
  expiry_date date NOT NULL,
  qty_on_hand numeric(12,3) NOT NULL CHECK (qty_on_hand >= 0),
  status text NOT NULL DEFAULT 'available' CHECK (status IN ('available','reserved','consumed','expired')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_batches_product_expiry ON batches(product_id, expiry_date);

CREATE TABLE inventory_transactions (
  trx_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  batch_id uuid NOT NULL REFERENCES batches(batch_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  location_id uuid NOT NULL REFERENCES locations(location_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  trx_type text NOT NULL CHECK (trx_type IN ('PZ','WZ','RW','ADJUST','RESERVE','RELEASE','EXPIRE','SCRAP')),
  qty numeric(12,3) NOT NULL,
  reason text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_by text
);

-- ===========
-- Plany produkcji
-- ===========
CREATE TABLE production_plans (
  plan_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  location_id uuid NOT NULL REFERENCES locations(location_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  plan_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','confirmed','completed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE production_plan_lines (
  plan_line_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan_id uuid NOT NULL REFERENCES production_plans(plan_id) ON UPDATE RESTRICT ON DELETE CASCADE,
  recipe_id uuid NOT NULL REFERENCES recipes(recipe_id),
  portions_planned integer NOT NULL CHECK (portions_planned >= 0),
  portions_actual integer,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','completed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ===========
-- Faktury
-- ===========
CREATE TABLE invoices (
  invoice_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  client_id uuid NOT NULL REFERENCES clients(client_id),
  period_start date NOT NULL,
  period_end date NOT NULL,
  status text NOT NULL CHECK (status IN ('Draft','Issued','Sent','Accepted','Rejected','Corrected')),
  net_amount numeric(12,2) NOT NULL,
  vat_amount numeric(12,2) NOT NULL,
  gross_amount numeric(12,2) NOT NULL,
  ksef_status text,
  ksef_number text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE invoice_items (
  invoice_item_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  invoice_id uuid NOT NULL REFERENCES invoices(invoice_id) ON UPDATE RESTRICT ON DELETE CASCADE,
  description text NOT NULL,
  meal_type text,
  diet_type text,
  qty integer NOT NULL CHECK (qty >= 0),
  unit text NOT NULL,
  unit_price numeric(12,2) NOT NULL,
  net numeric(12,2) NOT NULL,
  vat_rate numeric(5,2) NOT NULL,
  vat_amount numeric(12,2) NOT NULL,
  gross numeric(12,2) NOT NULL
);

-- ===========
-- Forecasts
-- ===========
CREATE TABLE forecasts (
  forecast_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id uuid NOT NULL REFERENCES products(product_id),
  location_id uuid NOT NULL REFERENCES locations(location_id),
  forecast_date date NOT NULL,
  qty numeric(12,3) NOT NULL,
  model text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ===== Inwentaryzacje (cycle counts) =====
CREATE TYPE inv_count_status AS ENUM ('draft','in_progress','counted','posted','canceled');

CREATE TABLE IF NOT EXISTS inventory_counts (
  count_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  location_id uuid NOT NULL REFERENCES locations(location_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  scope text NOT NULL CHECK (scope IN ('full','category','product','spot')),
  scheduled_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,
  status inv_count_status NOT NULL DEFAULT 'draft',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by text
);

-- Pozycje liczenia – liczymy per produkt (opcjonalnie per partia, jeśli chcesz większą precyzję)
CREATE TABLE IF NOT EXISTS inventory_count_lines (
  count_line_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  count_id uuid NOT NULL REFERENCES inventory_counts(count_id) ON UPDATE RESTRICT ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(product_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  -- stan teoretyczny na start liczenia:
  book_qty numeric(12,3) NOT NULL,
  -- suma po wszystkich partiach (jeśli liczysz po partiach, możesz dodać podtabelę szczegółową)
  counted_qty numeric(12,3) NOT NULL DEFAULT 0 CHECK (counted_qty >= 0),
  variance_qty numeric(12,3) NOT NULL DEFAULT 0,      -- counted - book
  reason text,                                        -- np. 'waste','breakage','transfer','shrinkage'
  notes text,
  UNIQUE(count_id, product_id)
);

-- Opcjonalnie: szczegóły per partia, jeśli chcesz liczyć z lotami
CREATE TABLE IF NOT EXISTS inventory_count_batches (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  count_line_id uuid NOT NULL REFERENCES inventory_count_lines(count_line_id) ON UPDATE RESTRICT ON DELETE CASCADE,
  batch_id uuid NOT NULL REFERENCES batches(batch_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
  counted_qty numeric(12,3) NOT NULL CHECK (counted_qty >= 0),
  UNIQUE(count_line_id, batch_id)
);
