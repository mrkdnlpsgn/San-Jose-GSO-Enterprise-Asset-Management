-- One PAR (Property Acknowledgement Receipt) is issued to an accountable officer and
-- can cover several property-numbered items on the same form, so the same PAR Number
-- legitimately repeats across asset rows. `par_number` was UNIQUE (uq_assets_par_no),
-- which forced one invented PAR per device. The property number stays the unique
-- identity of an asset; the PAR only gets a plain index for lookups.
--
-- Idempotent: safe to re-run.

SET @drop := (SELECT IF(COUNT(*) > 0,
    'ALTER TABLE assets DROP INDEX uq_assets_par_no',
    'SELECT ''uq_assets_par_no already dropped'' AS note')
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'assets' AND INDEX_NAME = 'uq_assets_par_no');
PREPARE stmt FROM @drop; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @add := (SELECT IF(COUNT(*) = 0,
    'ALTER TABLE assets ADD INDEX idx_assets_par_no (par_number)',
    'SELECT ''idx_assets_par_no already present'' AS note')
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'assets' AND INDEX_NAME = 'idx_assets_par_no');
PREPARE stmt FROM @add; EXECUTE stmt; DEALLOCATE PREPARE stmt;
