-- 0003_views_shrinkage.sql : Widoki raportowe dla różnic inwentaryzacyjnych

-- Widok rozbieżności ujemnych (niedobory) po inwentaryzacji
CREATE OR REPLACE VIEW vw_inventory_shrinkage AS
SELECT
  ic.count_id,
  ic.location_id,
  l.name         AS location_name,
  ic.started_at,
  ic.completed_at,
  ic.status,
  p.product_id,
  p.name         AS product_name,
  p.unit,
  icl.book_qty,
  icl.counted_qty,
  icl.variance_qty,                 -- < 0 dla niedoborów
  COALESCE(icl.reason,'unknown') AS reason,
  icl.notes
FROM inventory_counts ic
JOIN locations l              ON l.location_id = ic.location_id
JOIN inventory_count_lines icl ON icl.count_id = ic.count_id
JOIN products p               ON p.product_id = icl.product_id
WHERE ic.status = 'posted' AND icl.variance_qty < 0;

-- Agregacja miesięczna niedoborów per lokalizacja
CREATE OR REPLACE VIEW vw_inventory_shrinkage_monthly AS
SELECT
  ic.location_id,
  l.name AS location_name,
  date_trunc('month', ic.completed_at)::date AS month,
  COUNT(*) FILTER (WHERE icl.variance_qty < 0)     AS items_with_shrinkage,
  SUM(-icl.variance_qty)                           AS total_missing_qty
FROM inventory_counts ic
JOIN locations l ON l.location_id = ic.location_id
JOIN inventory_count_lines icl ON icl.count_id = ic.count_id
WHERE ic.status = 'posted' AND icl.variance_qty < 0
GROUP BY ic.location_id, l.name, date_trunc('month', ic.completed_at);
