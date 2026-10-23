-- =============================================================
-- Renames the seeded assets' property numbers from the 'SEED-YEAR-####'
-- placeholder format to the app's real 'COA-YEAR-###' format, so they're
-- indistinguishable from assets created through the UI.
--
-- Run this ONCE, right after seed_2000_assets.sql, before any real
-- COA-numbered assets are created for the affected years (otherwise
-- their per-year sequence continues from whatever's already there -
-- which is safe, just first-run-only by design since a second run
-- would find no more 'SEED-%' rows left to rename).
--
-- Step 1 records which asset_ids belong to the seed batch into a
-- permanent marker table (`seed_batch_assets`) BEFORE renaming, since
-- the 'SEED-' prefix - the only other way to identify this batch - is
-- about to be overwritten. cleanup_seed_2000_assets.sql depends on
-- this table to know what to remove later.
--
-- Run against whichever database you loaded the seed into:
--   mysql -u root gso_inventory < rename_seed_property_numbers.sql
-- =============================================================

CREATE TABLE IF NOT EXISTS seed_batch_assets (
  asset_id     INT          NOT NULL PRIMARY KEY,
  batch_label  VARCHAR(50)  NOT NULL DEFAULT 'seed_2000_assets',
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO seed_batch_assets (asset_id)
SELECT asset_id FROM assets WHERE property_number LIKE 'SEED-%';

-- Existing real COA sequence per year, so renamed rows continue after it
-- rather than colliding (the property_number UNIQUE constraint would
-- reject the whole statement if a collision occurred, so this is safe
-- to run even if the assumption above is somehow wrong).
CREATE TEMPORARY TABLE tmp_real_max AS
SELECT CAST(SUBSTRING(property_number, 5, 4) AS UNSIGNED) AS yr,
       MAX(CAST(SUBSTRING(property_number, 10) AS UNSIGNED)) AS max_seq
FROM assets
WHERE property_number REGEXP '^COA-[0-9]{4}-[0-9]+$'
GROUP BY yr;

CREATE TEMPORARY TABLE tmp_seed_rank AS
SELECT asset_id,
       CAST(SUBSTRING(property_number, 6, 4) AS UNSIGNED) AS yr,
       ROW_NUMBER() OVER (PARTITION BY CAST(SUBSTRING(property_number, 6, 4) AS UNSIGNED) ORDER BY asset_id) AS rn
FROM assets
WHERE property_number LIKE 'SEED-%';

UPDATE assets a
JOIN tmp_seed_rank r ON a.asset_id = r.asset_id
LEFT JOIN tmp_real_max m ON m.yr = r.yr
SET a.property_number = CONCAT('COA-', r.yr, '-', LPAD(COALESCE(m.max_seq, 0) + r.rn, 3, '0'));
