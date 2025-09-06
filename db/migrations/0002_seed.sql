-- 0002_seed.sql : Minimalne dane startowe (lokalizacja + produkty + przykładowa partia)
-- Używamy stabilnych UUID, których oczekują testy / przykłady.

-- Lokalizacja
INSERT INTO locations (location_id, name, created_by)
VALUES ('aaaa1111-1111-1111-1111-111111111111', 'Stołówka SP5', 'seed')
ON CONFLICT (location_id) DO NOTHING;

-- Produkty (co najmniej dwa, których używamy w testach)
INSERT INTO products (product_id, name, unit, allergen_codes, shelf_life_days) VALUES
  ('55555555-5555-5555-5555-555555555555', 'Marchew',   'kg', NULL, 14),
  ('66666666-6666-6666-6666-666666666666', 'Ziemniaki', 'kg', NULL, 30)
ON CONFLICT (product_id) DO NOTHING;

-- (opcjonalnie) dodatkowe dwa przykładowe produkty
INSERT INTO products (product_id, name, unit) VALUES
  ('77777777-7777-7777-7777-777777777777', 'Mleko 2%', 'l'),
  ('88888888-8888-8888-8888-888888888888', 'Cukier',   'kg')
ON CONFLICT (product_id) DO NOTHING;

-- (opcjonalnie) przykładowa partia marchwi — wygodne do szybkich testów
INSERT INTO batches (batch_id, product_id, supplier_id, lot_number, received_at, expiry_date, qty_on_hand, status)
VALUES (gen_random_uuid(), '55555555-5555-5555-5555-555555555555', NULL,
        'LOT-MAR-001', now(), current_date + 7, 100.000, 'available')
ON CONFLICT DO NOTHING;

-- Dziennik PZ (nieobowiązkowy, ale przydatny w weryfikacji)
INSERT INTO inventory_transactions (trx_id, batch_id, location_id, trx_type, qty, reason, created_by)
SELECT gen_random_uuid(), b.batch_id, 'aaaa1111-1111-1111-1111-111111111111', 'PZ', 100.000, 'seed', 'seed'
FROM batches b
WHERE b.product_id = '55555555-5555-5555-5555-555555555555'
ORDER BY b.received_at DESC
LIMIT 1;
