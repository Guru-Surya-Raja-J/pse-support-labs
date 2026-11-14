\echo '== Marina Bay (seller 3): imports with stuck invoices =='
SELECT im.id, im.status AS import_status, im.created_at,
  count(*) FILTER (WHERE i.status='Parsed') AS parsed, count(*) FILTER (WHERE i.status='Validated') AS validated,
  count(*) FILTER (WHERE i.status='Submitted') AS submitted, count(*) FILTER (WHERE i.status='Accepted') AS accepted
FROM imports im LEFT JOIN invoices i ON i.import_id = im.id
WHERE im.seller_id = 3
GROUP BY 1,2,3 HAVING count(*) FILTER (WHERE i.status IN ('Parsed','Validated','Submitted')) > 0 OR im.status <> 'Completed'
ORDER BY 3;

\echo '== Platform-wide: imports stuck in Processing (API killed mid-upload) =='
SELECT s.name, im.id, im.created_at, im.row_count FROM imports im JOIN sellers s ON s.id=im.seller_id WHERE im.status='Processing' ORDER BY im.created_at;
