-- Minimalny seed danych testowych dla systemu cateringowego

-- === Klienci ===
INSERT INTO clients (client_id, name, type, tax_id)
VALUES 
  ('11111111-1111-1111-1111-111111111111', 'Szkoła Podstawowa nr 5', 'school', 'PL1234567890'),
  ('22222222-2222-2222-2222-222222222222', 'Przedszkole nr 7', 'kindergarten', 'PL2345678901');

-- === Lokalizacje ===
INSERT INTO locations (location_id, client_id, name, address)
VALUES
  ('aaaa1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'SP5 – Stołówka', 'ul. Szkolna 1, Warszawa'),
  ('aaaa2222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Przedszkole 7 – Kuchnia', 'ul. Przedszkolna 2, Warszawa');

-- === Dostawcy ===
INSERT INTO suppliers (supplier_id, name, contact)
VALUES
  ('33333333-3333-3333-3333-333333333333', 'Hurtownia Warzywa i Owoce', 'warzywa@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'Mleko Sp. z o.o.', 'mleko@example.com');

-- === Produkty ===
INSERT INTO products (product_id, name, unit, allergen, shelf_life_days)
VALUES
  ('55555555-5555-5555-5555-555555555555', 'Marchew', 'kg', NULL, 14),
  ('66666666-6666-6666-6666-666666666666', 'Ziemniaki', 'kg', NULL, 30),
  ('77777777-7777-7777-7777-777777777777', 'Mleko 2%', 'l', 'milk', 7),
  ('88888888-8888-8888-8888-888888888888', 'Filet z kurczaka', 'kg', NULL, 5);

-- === Receptury ===
INSERT INTO recipes (recipe_id, name, meal_type, diet_type)
VALUES
  ('99999999-9999-9999-9999-999999999999', 'Zupa marchewkowa', 'lunch', 'std');

-- Składniki do receptury
INSERT INTO recipe_items (recipe_item_id, recipe_id, product_id, qty_per_portion, loss_pct)
VALUES
  ('aaaa9999-9999-9999-9999-999999999999', '99999999-9999-9999-9999-999999999999', '55555555-5555-5555-5555-555555555555', 0.150, 5.0),
  ('bbbb9999-9999-9999-9999-999999999999', '99999999-9999-9999-9999-999999999999', '77777777-7777-7777-7777-777777777777', 0.200, 2.0);

-- === Menu (na jeden dzień) ===
INSERT INTO menus (menu_id, location_id, date, recipe_id)
VALUES
  ('cccc9999-9999-9999-9999-999999999999', 'aaaa1111-1111-1111-1111-111111111111', CURRENT_DATE, '99999999-9999-9999-9999-999999999999');

-- === Zamówienia ===
INSERT INTO orders (order_id, location_id, order_date, cutoff_time)
VALUES
  ('dddd9999-9999-9999-9999-999999999999', 'aaaa1111-1111-1111-1111-111111111111', CURRENT_DATE, '09:00');

INSERT INTO order_items (order_item_id, order_id, menu_id, portions)
VALUES
  ('eeee9999-9999-9999-9999-999999999999', 'dddd9999-9999-9999-9999-999999999999', 'cccc9999-9999-9999-9999-999999999999', 30);

-- === Partie w magazynie (batches) ===
INSERT INTO batches (batch_id, product_id, supplier_id, lot_number, received_at, expiry_date, qty_on_hand, status)
VALUES
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', '55555555-5555-5555-5555-555555555555', '33333333-3333-3333-3333-333333333333', 'LOT-MAR-001', now() - interval '1 day', CURRENT_DATE + 7, 100.0, 'available');

-- Transakcja przyjęcia na magazyn (PZ)
INSERT INTO inventory_transactions (trx_id, batch_id, location_id, trx_type, qty, reason, created_by)
VALUES
  ('abcdabcd-abcd-abcd-abcd-abcdabcdabcd', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'aaaa1111-1111-1111-1111-111111111111', 'PZ', 100.0, 'Initial seed stock', 'seed-script');
