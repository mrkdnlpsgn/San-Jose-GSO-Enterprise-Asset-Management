-- Disposal methods changed from AUCTION | DONATION | TRANSFER to SALE | TRANSFER | DESTRUCTION | OTHERS.
-- Run once on a database created before that change (safe to re-run):
--   mysql -u<user> -p <database> < backend_sj/migrate_disposal_methods.sql
-- Hibernate's ddl-auto=update never alters an existing enum column, so the old column would reject the
-- new values ("Data truncated for column 'recommended_method'").

ALTER TABLE disposal_ledger MODIFY COLUMN recommended_method VARCHAR(20) NOT NULL;

UPDATE disposal_ledger SET recommended_method = CASE recommended_method
  WHEN 'AUCTION' THEN 'SALE' WHEN 'DONATION' THEN 'TRANSFER' ELSE recommended_method END
WHERE recommended_method IN ('AUCTION', 'DONATION');

UPDATE deleted_disposal SET recommended_method = CASE recommended_method
  WHEN 'AUCTION' THEN 'SALE' WHEN 'DONATION' THEN 'TRANSFER' ELSE recommended_method END
WHERE recommended_method IN ('AUCTION', 'DONATION');
