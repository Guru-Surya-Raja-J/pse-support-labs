\echo '== Invoices by seller and status =='
SELECT s.id AS seller_id, s.name, i.status, count(*)
FROM invoices i JOIN sellers s ON s.id = i.seller_id
GROUP BY 1,2,3 ORDER BY 1,3;

\echo '== Imports by seller and status (with timing) =='
SELECT s.name, im.status, count(*), round(avg(im.duration_ms)/1000.0,1) AS avg_s, round(max(im.duration_ms)/1000.0,1) AS max_s
FROM imports im JOIN sellers s ON s.id = im.seller_id
GROUP BY 1,2 ORDER BY 1,2;

\echo '== Invoices stuck (Parsed / Validated / Submitted) older than 2 minutes, by seller =='
SELECT s.name, i.status, count(*), min(i.updated_at) AS oldest, max(i.updated_at) AS newest
FROM invoices i JOIN sellers s ON s.id = i.seller_id
WHERE i.status IN ('Parsed','Validated','Submitted') AND i.updated_at < now() - interval '2 minutes'
GROUP BY 1,2 ORDER BY 1,2;
