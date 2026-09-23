-- =============================================================
-- migrate_rbac.sql — approval workflow for maintenance / disposal records.
-- Staff-created records start as PENDING_APPROVAL until an admin approves or
-- rejects them; existing rows (and admin/system-created ones) are APPROVED.
--
-- Idempotent. Run, then reload stored_procedures.sql:
--   docker exec -i sj_gso_db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < backend_sj/migrate_rbac.sql
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

CALL _mig_add_column('maintenance_ledger', 'approval_status', 'varchar(20) NOT NULL DEFAULT ''APPROVED''');
CALL _mig_add_column('maintenance_ledger', 'requested_by', 'int(11) DEFAULT NULL');
CALL _mig_add_column('maintenance_ledger', 'reviewed_by', 'int(11) DEFAULT NULL');
CALL _mig_add_column('maintenance_ledger', 'reviewed_at', 'datetime DEFAULT NULL');
CALL _mig_add_column('maintenance_ledger', 'review_note', 'varchar(255) DEFAULT NULL');

CALL _mig_add_column('disposal_ledger', 'approval_status', 'varchar(20) NOT NULL DEFAULT ''APPROVED''');
CALL _mig_add_column('disposal_ledger', 'requested_by', 'int(11) DEFAULT NULL');
CALL _mig_add_column('disposal_ledger', 'reviewed_by', 'int(11) DEFAULT NULL');
CALL _mig_add_column('disposal_ledger', 'reviewed_at', 'datetime DEFAULT NULL');
CALL _mig_add_column('disposal_ledger', 'review_note', 'varchar(255) DEFAULT NULL');

DROP PROCEDURE IF EXISTS _mig_add_column;
