-- =============================================================
-- migrate_nuque.sql — brings an EXISTING database up to the schema
-- Branch-Nuque expects (PAR numbers, asset grouping, specifications,
-- current user, evidence photos, delete-OTP, new disposal methods).
--
-- gso_inventory.sql only creates these on a brand-new, empty database
-- (docker-entrypoint-initdb.d runs once), and Docker runs Hibernate with
-- ddl-auto=validate, so without this the backend refuses to start.
--
-- Idempotent: every step checks information_schema first, so it is safe
-- to run more than once. Not reversible — restore from a mysqldump backup
-- to roll back. After this, the AUCTION/DONATION disposal rows become
-- SALE/TRANSFER, which older branches' DisposalMethod enum cannot read.
--
-- Run (Docker):
--   docker exec -i sj_gso_db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < backend_sj/migrate_nuque.sql
-- Then reload the procedures from this branch:
--   docker exec -i sj_gso_db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < backend_sj/stored_procedures.sql
-- =============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS _mig_add_column $$
CREATE PROCEDURE _mig_add_column(IN p_table VARCHAR(64), IN p_column VARCHAR(64), IN p_definition TEXT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND COLUMN_NAME = p_column) THEN
        SET @ddl := CONCAT('ALTER TABLE `', p_table, '` ADD COLUMN `', p_column, '` ', p_definition);
        PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    END IF;
END $$

DROP PROCEDURE IF EXISTS _mig_add_index $$
CREATE PROCEDURE _mig_add_index(IN p_table VARCHAR(64), IN p_index VARCHAR(64), IN p_definition TEXT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND INDEX_NAME = p_index) THEN
        SET @ddl := CONCAT('ALTER TABLE `', p_table, '` ADD ', p_definition);
        PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    END IF;
END $$

DROP PROCEDURE IF EXISTS _mig_add_fk $$
CREATE PROCEDURE _mig_add_fk(IN p_table VARCHAR(64), IN p_fk VARCHAR(64), IN p_definition TEXT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table
                     AND CONSTRAINT_NAME = p_fk AND CONSTRAINT_TYPE = 'FOREIGN KEY') THEN
        SET @ddl := CONCAT('ALTER TABLE `', p_table, '` ADD CONSTRAINT `', p_fk, '` ', p_definition);
        PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    END IF;
END $$

DELIMITER ;

-- -------------------------------------------------------------
-- assets: PAR number, specifications, grouping, current user
-- -------------------------------------------------------------
CALL _mig_add_column('assets', 'par_number',
    'varchar(50) DEFAULT NULL COMMENT ''Property Acknowledgment Receipt no. - YYYY-MM:SERIAL (acquisition year-month + manually entered serial)'' AFTER `property_number`');
CALL _mig_add_column('assets', 'specifications', 'text DEFAULT NULL');
CALL _mig_add_column('assets', 'group_id', 'varchar(36) DEFAULT NULL');
CALL _mig_add_column('assets', 'current_user_personnel_id', 'int(11) DEFAULT NULL AFTER `personnel_id`');

CALL _mig_add_index('assets', 'uq_assets_par_no', 'UNIQUE KEY `uq_assets_par_no` (`par_number`)');
CALL _mig_add_index('assets', 'idx_assets_group', 'KEY `idx_assets_group` (`group_id`)');
CALL _mig_add_index('assets', 'idx_assets_current_user', 'KEY `idx_assets_current_user` (`current_user_personnel_id`)');
CALL _mig_add_fk('assets', 'fk_assets_current_user',
    'FOREIGN KEY (`current_user_personnel_id`) REFERENCES `personnel` (`personnel_id`) ON UPDATE CASCADE');

-- -------------------------------------------------------------
-- Recycle Bin snapshots
-- -------------------------------------------------------------
CALL _mig_add_column('deleted_assets', 'par_number', 'varchar(50) DEFAULT NULL AFTER `property_number`');
CALL _mig_add_column('deleted_assets', 'specifications', 'text DEFAULT NULL');
CALL _mig_add_column('deleted_assets', 'current_user_personnel_id', 'bigint(20) DEFAULT NULL');
CALL _mig_add_column('deleted_assets', 'current_user_name',
    'varchar(150) DEFAULT NULL COMMENT ''Snapshot of current user name at deletion''');
CALL _mig_add_column('deleted_disposal', 'par_number',
    'varchar(50) DEFAULT NULL COMMENT ''Snapshot of PAR number'' AFTER `property_number`');
CALL _mig_add_column('deleted_maintenance', 'par_number',
    'varchar(50) DEFAULT NULL COMMENT ''Snapshot of PAR number'' AFTER `property_number`');

-- -------------------------------------------------------------
-- users: step-up OTP for permanent Recycle Bin deletes
-- -------------------------------------------------------------
CALL _mig_add_column('users', 'delete_otp_hash', 'varchar(255) DEFAULT NULL');
CALL _mig_add_column('users', 'delete_otp_expires_at', 'datetime DEFAULT NULL');
CALL _mig_add_column('users', 'delete_otp_attempts', 'int(11) NOT NULL DEFAULT 0');

-- -------------------------------------------------------------
-- evidence_photos: asset + disposal evidence
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `evidence_photos` (
  `photo_id` bigint(20) NOT NULL AUTO_INCREMENT,
  `target_type` varchar(20) NOT NULL COMMENT 'ASSET | DISPOSAL',
  `target_id` bigint(20) NOT NULL,
  `file_path` varchar(255) NOT NULL,
  `original_filename` varchar(255) DEFAULT NULL,
  `content_type` varchar(100) DEFAULT NULL,
  `file_size` bigint(20) DEFAULT NULL,
  `uploaded_by` int(11) DEFAULT NULL,
  `uploaded_at` datetime NOT NULL,
  PRIMARY KEY (`photo_id`),
  KEY `idx_evidence_target` (`target_type`,`target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- -------------------------------------------------------------
-- maintenance_photos: was only ever created by Hibernate (ddl-auto=update),
-- so a database built purely from the SQL files lacks it and fails
-- ddl-auto=validate. Its FK also had no ON DELETE rule, which made
-- sp_maintenance_permanent_delete / sp_assets_permanent_delete fail for any
-- maintenance record with photos. Cascade the rows (photo files on disk
-- still need removing in application code).
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `maintenance_photos` (
  `photo_id` bigint NOT NULL AUTO_INCREMENT,
  `content_type` varchar(100) DEFAULT NULL,
  `file_path` varchar(255) NOT NULL,
  `file_size` bigint DEFAULT NULL,
  `original_filename` varchar(255) DEFAULT NULL,
  `uploaded_at` datetime(6) NOT NULL,
  `maintenance_id` bigint NOT NULL,
  `uploaded_by` bigint DEFAULT NULL,
  PRIMARY KEY (`photo_id`),
  KEY `FKa4kfyvkam1pekrlcnbburdt1x` (`maintenance_id`),
  CONSTRAINT `FKa4kfyvkam1pekrlcnbburdt1x` FOREIGN KEY (`maintenance_id`)
    REFERENCES `maintenance_ledger` (`maintenance_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

SET @photo_fk := (SELECT CONSTRAINT_NAME FROM information_schema.REFERENTIAL_CONSTRAINTS
                  WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'maintenance_photos'
                    AND REFERENCED_TABLE_NAME = 'maintenance_ledger' AND DELETE_RULE <> 'CASCADE'
                  LIMIT 1);
SET @sql := IF(@photo_fk IS NULL, 'DO 0',
    CONCAT('ALTER TABLE `maintenance_photos` DROP FOREIGN KEY `', @photo_fk, '`'));
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @sql := IF(@photo_fk IS NULL, 'DO 0',
    CONCAT('ALTER TABLE `maintenance_photos` ADD CONSTRAINT `', @photo_fk,
           '` FOREIGN KEY (`maintenance_id`) REFERENCES `maintenance_ledger` (`maintenance_id`) ON DELETE CASCADE'));
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- -------------------------------------------------------------
-- Disposal methods: AUCTION/DONATION/TRANSFER enum -> SALE/TRANSFER/DESTRUCTION/OTHERS
-- (same as migrate_disposal_methods.sql, guarded so it only alters once)
-- -------------------------------------------------------------
SET @is_enum := (SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'disposal_ledger'
                   AND COLUMN_NAME = 'recommended_method' AND DATA_TYPE = 'enum');
SET @sql := IF(@is_enum = 0, 'DO 0',
    'ALTER TABLE `disposal_ledger` MODIFY COLUMN `recommended_method` varchar(20) NOT NULL COMMENT ''SALE | TRANSFER | DESTRUCTION | OTHERS (older data used AUCTION | DONATION | TRANSFER)''');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

UPDATE `disposal_ledger` SET `recommended_method` = CASE `recommended_method`
  WHEN 'AUCTION' THEN 'SALE' WHEN 'DONATION' THEN 'TRANSFER' ELSE `recommended_method` END
WHERE `recommended_method` IN ('AUCTION', 'DONATION');

UPDATE `deleted_disposal` SET `recommended_method` = CASE `recommended_method`
  WHEN 'AUCTION' THEN 'SALE' WHEN 'DONATION' THEN 'TRANSFER' ELSE `recommended_method` END
WHERE `recommended_method` IN ('AUCTION', 'DONATION');

-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS _mig_add_column;
DROP PROCEDURE IF EXISTS _mig_add_index;
DROP PROCEDURE IF EXISTS _mig_add_fk;
