-- =============================================================
-- migrate_shortage_overage.sql — manually recorded shortage (negative) / overage
-- (positive) found during physical inventory, independent of quantity/physicalCount.
-- Matches the column definitions in gso_inventory.sql; sp_assets_create/update/list
-- in stored_procedures.sql read and write these.
--
-- Idempotent:
--   docker exec -i sj_gso_db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < backend_sj/migrate_shortage_overage.sql
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
DELIMITER ;

CALL _mig_add_column('assets', 'shortage_overage_qty',
    'int NOT NULL DEFAULT 0 COMMENT ''Manually recorded shortage (negative) or overage (positive) count found during physical inventory''');
CALL _mig_add_column('assets', 'shortage_overage_value',
    'decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT ''Manually recorded peso value of the shortage/overage''');

DROP PROCEDURE IF EXISTS _mig_add_column;
