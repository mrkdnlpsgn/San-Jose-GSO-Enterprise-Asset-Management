-- =============================================================
-- PERSONNEL migration — introduces a proper Personnel record for
-- Asset.accountable_person instead of a free-text name.
--
-- Run this once against an EXISTING database (docker-entrypoint-initdb.d
-- scripts only execute on a brand-new, empty data volume, so a database
-- that already has data needs this run by hand):
--
--   docker exec -i sj_gso_db mysql -u root -p<password> sj_gso_inventory < migration_personnel.sql
--
-- Idempotent — every step is guarded so re-running it is a no-op. This
-- exact script is also appended to gso_inventory.sql so a fresh install
-- (empty volume) ends up with the identical schema.
-- =============================================================

CREATE TABLE IF NOT EXISTS `personnel` (
  `personnel_id` int(11) NOT NULL AUTO_INCREMENT,
  `full_name` varchar(150) NOT NULL,
  `position` varchar(150) DEFAULT NULL,
  `office_id` int(11) DEFAULT NULL,
  `contact_info` varchar(150) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`personnel_id`),
  UNIQUE KEY `uq_personnel_full_name` (`full_name`),
  KEY `idx_personnel_office` (`office_id`),
  CONSTRAINT `fk_personnel_office` FOREIGN KEY (`office_id`) REFERENCES `offices` (`office_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Add assets.personnel_id if this is the first time this script runs.
SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'assets' AND COLUMN_NAME = 'personnel_id'
);
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE `assets` ADD COLUMN `personnel_id` int(11) DEFAULT NULL AFTER `office_id`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Backfill: one Personnel row per distinct existing accountable_person name,
-- then point every asset at its matching row (case-insensitive, trimmed).
SET @acc_col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'assets' AND COLUMN_NAME = 'accountable_person'
);

SET @sql := IF(@acc_col_exists = 1,
  'INSERT INTO `personnel` (full_name, created_at)
   SELECT DISTINCT TRIM(accountable_person), NOW() FROM `assets`
   WHERE accountable_person IS NOT NULL AND TRIM(accountable_person) <> ""
     AND TRIM(accountable_person) NOT IN (SELECT full_name FROM personnel)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql := IF(@acc_col_exists = 1,
  'UPDATE `assets` a JOIN `personnel` p ON LOWER(TRIM(a.accountable_person)) = LOWER(p.full_name)
   SET a.personnel_id = p.personnel_id
   WHERE a.personnel_id IS NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Drop the now-superseded free-text column + its index (only if still present).
SET @sql := IF(@acc_col_exists = 1,
  'ALTER TABLE `assets` DROP INDEX `idx_assets_accountable`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql := IF(@acc_col_exists = 1,
  'ALTER TABLE `assets` DROP COLUMN `accountable_person`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Add the new index + FK (only if not already added by a prior run).
SET @fk_exists := (
  SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'assets' AND CONSTRAINT_NAME = 'fk_assets_personnel'
);
SET @sql := IF(@fk_exists = 0,
  'ALTER TABLE `assets`
     ADD KEY `idx_assets_personnel` (`personnel_id`),
     ADD CONSTRAINT `fk_assets_personnel` FOREIGN KEY (`personnel_id`) REFERENCES `personnel` (`personnel_id`) ON UPDATE CASCADE',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
