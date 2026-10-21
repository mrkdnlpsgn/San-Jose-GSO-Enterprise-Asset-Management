-- Cleans up asset rows left over from the old grouping and multi-quantity models.
-- Safe to run more than once; matches rows by property number, not asset_id, so the same file
-- works on any copy of the database. Take a backup first.
--
--   1. Clears leftover group_id values. Grouping was removed when assets became single-quantity,
--      but the mobile list still merged assets that shared a group_id into one "N devices" row.
--   2. Splits every row with quantity > 1 into one row per item. Item 1 keeps the original
--      property number; items 2..N get "<property number>-2" ... "-N". Physical count is spread
--      over the items (the first <count> items count as found). Items under maintenance or pending
--      disposal each get a copy of the original's active record, with cost/amounts left blank so
--      money isn't counted twice.
--   3. Soft-deletes the test record TEST-DEBUG-003 (restorable from the Recycle Bin).
--
-- QR signatures for the new rows are issued by the backend on its next start.

DROP PROCEDURE IF EXISTS tmp_fix_asset_rows;
DELIMITER $$
CREATE PROCEDURE tmp_fix_asset_rows()
BEGIN
  DECLARE admin_id INT;
  DECLARE test_id INT;
  SELECT user_id INTO admin_id FROM users WHERE role = 'ADMIN' ORDER BY user_id LIMIT 1;

  START TRANSACTION;

  -- 1. Leftover groups
  UPDATE assets SET group_id = NULL, updated_at = updated_at WHERE group_id IS NOT NULL;
  SELECT ROW_COUNT() AS groups_cleared;

  -- 2. Multi-quantity rows
  -- Scratch tables declare a primary key: hosted MySQL (Aiven) sets sql_require_primary_key.
  DROP TEMPORARY TABLE IF EXISTS split_src;
  CREATE TEMPORARY TABLE split_src (
    asset_id INT PRIMARY KEY, property_number VARCHAR(50), quantity INT, physical_count INT);
  INSERT INTO split_src
    SELECT asset_id, property_number, quantity, physical_count
    FROM assets WHERE is_deleted = 0 AND quantity > 1;

  INSERT INTO assets (property_number, par_number, serial_number, description, category_id, quantity,
                      acquisition_date, unit_value, office_id, personnel_id, current_user_personnel_id,
                      physical_count, location, `condition`, lifecycle_status, qr_code_path, sha256_hash,
                      remarks, specifications, group_id, shortage_overage_qty, shortage_overage_value,
                      is_deleted, created_at, updated_at)
  WITH RECURSIVE n AS (SELECT 2 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 1000)
  SELECT CONCAT(a.property_number, '-', n.i), a.par_number, NULL, a.description, a.category_id, 1,
         a.acquisition_date, a.unit_value, a.office_id, a.personnel_id, a.current_user_personnel_id,
         CASE WHEN a.physical_count IS NULL THEN NULL WHEN n.i <= a.physical_count THEN 1 ELSE 0 END,
         a.location, a.`condition`, a.lifecycle_status, NULL, NULL,
         a.remarks, a.specifications, NULL, 0, 0,
         0, a.created_at, NOW()
  FROM assets a
  JOIN split_src s ON s.asset_id = a.asset_id
  JOIN n ON n.i <= a.quantity
  WHERE NOT EXISTS (SELECT 1 FROM assets x WHERE x.property_number = CONCAT(a.property_number, '-', n.i));
  SELECT ROW_COUNT() AS item_rows_added;

  DROP TEMPORARY TABLE IF EXISTS split_map;
  CREATE TEMPORARY TABLE split_map (
    new_id INT PRIMARY KEY, orig_id INT, orig_no VARCHAR(50), orig_qty INT, new_no VARCHAR(60));
  INSERT INTO split_map (orig_id, orig_no, orig_qty, new_id, new_no)
    SELECT s.asset_id AS orig_id, s.property_number AS orig_no, s.quantity AS orig_qty, c.asset_id AS new_id, c.property_number AS new_no
    FROM split_src s
    JOIN assets c ON c.property_number LIKE CONCAT(s.property_number, '-%')
     AND SUBSTRING(c.property_number, CHAR_LENGTH(s.property_number) + 2) REGEXP '^[0-9]+$';

  -- Active maintenance record, one per new item
  INSERT INTO maintenance_ledger (asset_id, maintenance_type, findings, actions_taken, assigned_to, maintenance_date,
                                  cost, status, recorded_by, is_deleted, created_at, updated_at, approval_status,
                                  requested_by, reviewed_by, reviewed_at, review_note, requested_condition)
  SELECT m.new_id, l.maintenance_type, l.findings, l.actions_taken, l.assigned_to, l.maintenance_date,
         NULL, l.status, l.recorded_by, 0, l.created_at, NOW(), l.approval_status,
         l.requested_by, l.reviewed_by, l.reviewed_at, l.review_note, l.requested_condition
  FROM split_map m
  JOIN maintenance_ledger l ON l.maintenance_id = (
    SELECT l2.maintenance_id FROM maintenance_ledger l2
    WHERE l2.asset_id = m.orig_id AND l2.is_deleted = 0 AND l2.status IN ('ONGOING', 'SCHEDULED')
    ORDER BY l2.maintenance_date DESC, l2.maintenance_id DESC LIMIT 1)
  WHERE NOT EXISTS (SELECT 1 FROM maintenance_ledger z WHERE z.asset_id = m.new_id);
  SELECT ROW_COUNT() AS maintenance_records_added;

  -- Active disposal record, one per new item
  INSERT INTO disposal_ledger (asset_id, reason, inspection_findings, recommended_method, disposal_status,
                               inspection_date, approved_by, appraised_value, or_number, amount, recorded_by,
                               is_deleted, created_at, updated_at, approval_status, requested_by, reviewed_by,
                               reviewed_at, review_note, requested_condition)
  SELECT m.new_id, d.reason, d.inspection_findings, d.recommended_method, d.disposal_status,
         d.inspection_date, d.approved_by, NULL, NULL, NULL, d.recorded_by,
         0, d.created_at, NOW(), d.approval_status, d.requested_by, d.reviewed_by,
         d.reviewed_at, d.review_note, d.requested_condition
  FROM split_map m
  JOIN disposal_ledger d ON d.disposal_id = (
    SELECT d2.disposal_id FROM disposal_ledger d2
    WHERE d2.asset_id = m.orig_id AND d2.is_deleted = 0 AND d2.disposal_status <> 'COMPLETED'
    ORDER BY d2.inspection_date DESC, d2.disposal_id DESC LIMIT 1)
  WHERE NOT EXISTS (SELECT 1 FROM disposal_ledger z WHERE z.asset_id = m.new_id);
  SELECT ROW_COUNT() AS disposal_records_added;

  INSERT INTO asset_history (asset_id, event_type, from_office_id, to_office_id, performed_by, event_date, notes)
  SELECT m.new_id, 'REGISTERED', NULL, a.office_id, admin_id, NOW(),
         CONCAT('Asset registered: ', m.new_no, ' (split from ', m.orig_no, ', a Qty ', m.orig_qty, ' record; one row per item)')
  FROM split_map m JOIN assets a ON a.asset_id = m.new_id
  WHERE NOT EXISTS (SELECT 1 FROM asset_history h WHERE h.asset_id = m.new_id AND h.event_type = 'REGISTERED');

  -- Item 1 keeps the original row
  UPDATE assets a JOIN split_src s ON s.asset_id = a.asset_id
  SET a.quantity = 1,
      a.physical_count = CASE WHEN s.physical_count IS NULL THEN NULL WHEN s.physical_count >= 1 THEN 1 ELSE 0 END;
  SELECT ROW_COUNT() AS original_rows_set_to_qty_1;

  -- 3. Test record
  SELECT asset_id INTO test_id FROM assets WHERE property_number = 'TEST-DEBUG-003' AND is_deleted = 0 LIMIT 1;
  IF test_id IS NOT NULL THEN
    CALL sp_maintenance_soft_delete_by_asset(test_id, admin_id, 'admin', 'Test record, not a real asset');
    CALL sp_disposal_soft_delete_by_asset(test_id, admin_id, 'admin', 'Test record, not a real asset');
    CALL sp_assets_soft_delete(test_id, admin_id, 'admin', 'Test record, not a real asset');
  END IF;
  SELECT IF(test_id IS NULL, 'not found / already deleted', 'soft-deleted') AS test_debug_003;

  COMMIT;
END$$
DELIMITER ;

CALL tmp_fix_asset_rows();
DROP PROCEDURE tmp_fix_asset_rows;
