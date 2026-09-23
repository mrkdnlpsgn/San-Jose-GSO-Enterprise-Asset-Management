-- =============================================================
-- migrate_personnel_accounts.sql — links personnel records to login
-- accounts (personnel.user_id -> users.user_id, at most one account per
-- person). For databases created before this column existed; fresh
-- installs get it from gso_inventory.sql.
--
-- Idempotent. Reload stored_procedures.sql first, then run:
--   docker exec -i sj_gso_db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < backend_sj/migrate_personnel_accounts.sql
-- =============================================================

SET @has_col := (SELECT COUNT(*) FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'personnel' AND COLUMN_NAME = 'user_id');
SET @sql := IF(@has_col = 0,
    'ALTER TABLE `personnel` ADD COLUMN `user_id` int(11) DEFAULT NULL AFTER `contact_info`',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_idx := (SELECT COUNT(*) FROM information_schema.STATISTICS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'personnel' AND INDEX_NAME = 'uq_personnel_user');
SET @sql := IF(@has_idx = 0,
    'ALTER TABLE `personnel` ADD UNIQUE KEY `uq_personnel_user` (`user_id`)',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_fk := (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'personnel'
                  AND CONSTRAINT_NAME = 'fk_personnel_user' AND CONSTRAINT_TYPE = 'FOREIGN KEY');
SET @sql := IF(@has_fk = 0,
    'ALTER TABLE `personnel` ADD CONSTRAINT `fk_personnel_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL',
    'DO 0');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Every account gets its personnel record (needs sp_personnel_sync_accounts from
-- stored_procedures.sql — reload that file first, then run this one).
CALL sp_personnel_sync_accounts();
