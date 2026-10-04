-- =============================================================
-- migrate_request_condition.sql — a staff maintenance/disposal request can carry the
-- asset condition the staff asked for (REPAIRABLE / UNSERVICEABLE). The asset keeps its
-- current condition until an admin approves; approve() then applies this value.
--
-- Idempotent:
--   docker exec -i sj_gso_db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < backend_sj/migrate_request_condition.sql
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

CALL _mig_add_column('maintenance_ledger', 'requested_condition', 'varchar(20) DEFAULT NULL');
CALL _mig_add_column('disposal_ledger', 'requested_condition', 'varchar(20) DEFAULT NULL');

DROP PROCEDURE IF EXISTS _mig_add_column;
