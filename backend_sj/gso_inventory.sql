-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Jul 06, 2026 at 09:06 AM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.0.30

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `gso_inventory`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_ai_recommendations_create` (IN `p_asset_id` INT, IN `p_asset_age_years` DECIMAL(5,2), IN `p_total_repair_cost` DECIMAL(12,2), IN `p_repair_frequency` INT, IN `p_condition_score` INT, IN `p_recommendation` VARCHAR(30), IN `p_rationale` TEXT, OUT `p_id` INT)   BEGIN
    INSERT INTO ai_recommendations(
        asset_id, asset_age_years, total_repair_cost, repair_frequency,
        condition_score, recommendation, rationale, generated_at, generated_by_system
    ) VALUES (
        p_asset_id, p_asset_age_years, p_total_repair_cost, p_repair_frequency,
        p_condition_score, p_recommendation, p_rationale, NOW(), TRUE
    );
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_ai_recommendations_get_latest_by_asset` (IN `p_asset_id` INT)   BEGIN
    SELECT r.recommendation_id AS id, r.asset_age_years, r.total_repair_cost,
           r.repair_frequency, r.condition_score, r.recommendation, r.rationale,
           r.generated_at, r.generated_by_system,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description
    FROM ai_recommendations r
    JOIN assets a ON r.asset_id = a.asset_id
    WHERE r.asset_id = p_asset_id
    ORDER BY r.generated_at DESC
    LIMIT 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_ai_recommendations_summary` ()   BEGIN
    SELECT r.recommendation, COUNT(*) AS cnt
    FROM ai_recommendations r
    INNER JOIN (
        SELECT asset_id, MAX(generated_at) AS max_gen
        FROM ai_recommendations
        GROUP BY asset_id
    ) latest ON r.asset_id = latest.asset_id AND r.generated_at = latest.max_gen
    GROUP BY r.recommendation;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_assets_create` (IN `p_property_number` VARCHAR(50), IN `p_description` VARCHAR(255), IN `p_category_id` INT, IN `p_quantity` INT, IN `p_acquisition_date` DATE, IN `p_unit_value` DECIMAL(12,2), IN `p_office_id` INT, IN `p_accountable_person` VARCHAR(150), IN `p_physical_count` INT, IN `p_location` VARCHAR(150), IN `p_condition` VARCHAR(20), IN `p_lifecycle_status` VARCHAR(30), IN `p_qr_code_path` VARCHAR(255), IN `p_sha256_hash` VARCHAR(64), IN `p_remarks` TEXT, OUT `p_id` INT)   BEGIN
    INSERT INTO assets(
        property_number, `description`, category_id, quantity, acquisition_date,
        unit_value, office_id, accountable_person, physical_count, location, `condition`,
        lifecycle_status, qr_code_path, sha256_hash, remarks,
        is_deleted, created_at, updated_at
    ) VALUES (
        p_property_number, p_description, p_category_id, p_quantity, p_acquisition_date,
        p_unit_value, p_office_id, p_accountable_person, p_physical_count, p_location, p_condition,
        p_lifecycle_status, NULLIF(p_qr_code_path, ''), NULLIF(p_sha256_hash, ''), NULLIF(p_remarks, ''),
        FALSE, NOW(), NOW()
    );
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_assets_get_by_id` (IN `p_id` INT)   BEGIN
    SELECT a.asset_id AS id, a.property_number AS propertyNumber, a.`description`,
           a.quantity, a.acquisition_date AS acquisitionDate, a.unit_value AS unitValue,
           a.location, a.`condition`, a.lifecycle_status AS lifecycleStatus,
           a.accountable_person AS accountablePerson, a.physical_count AS physicalCount,
           a.qr_code_path AS qrCodePath, a.sha256_hash AS sha256Hash,
           a.remarks, a.created_at AS createdAt, a.updated_at AS updatedAt,
           c.category_id, c.category_name AS categoryName,
           o.office_id, o.office_name AS officeName
    FROM assets a
    LEFT JOIN categories c ON a.category_id = c.category_id
    LEFT JOIN offices o ON a.office_id = o.office_id
    WHERE a.asset_id = p_id AND a.is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_assets_list` (IN `p_search` VARCHAR(255), IN `p_limit` INT, IN `p_offset` INT, IN `p_category_id` INT, IN `p_office_id` INT, IN `p_condition` VARCHAR(20), IN `p_lifecycle_status` VARCHAR(30))   BEGIN
    SET p_search = TRIM(p_search);
    SELECT a.asset_id AS id, a.property_number AS propertyNumber, a.`description`,
           a.quantity, a.acquisition_date AS acquisitionDate, a.unit_value AS unitValue,
           a.location, a.`condition`, a.lifecycle_status AS lifecycleStatus,
           a.accountable_person AS accountablePerson, a.physical_count AS physicalCount,
           a.qr_code_path AS qrCodePath, a.sha256_hash AS sha256Hash,
           a.remarks, a.created_at AS createdAt, a.updated_at AS updatedAt,
           c.category_id, c.category_name AS categoryName,
           o.office_id, o.office_name AS officeName
    FROM assets a
    LEFT JOIN categories c ON a.category_id = c.category_id
    LEFT JOIN offices o ON a.office_id = o.office_id
    WHERE a.is_deleted = FALSE
      AND (
        p_search IS NULL OR p_search = '' OR
        a.property_number    LIKE CONCAT('%', p_search, '%')
        OR a.`description`   LIKE CONCAT('%', p_search, '%')
        OR a.accountable_person LIKE CONCAT('%', p_search, '%')
        OR a.location        LIKE CONCAT('%', p_search, '%')
        OR a.`condition`     LIKE CONCAT('%', p_search, '%')
        OR a.lifecycle_status LIKE CONCAT('%', p_search, '%')
        OR c.category_name   LIKE CONCAT('%', p_search, '%')
        OR o.office_name     LIKE CONCAT('%', p_search, '%')
      )
      AND (p_category_id IS NULL OR a.category_id = p_category_id)
      AND (p_office_id IS NULL OR a.office_id = p_office_id)
      AND (p_condition IS NULL OR p_condition = '' OR a.`condition` = p_condition)
      AND (p_lifecycle_status IS NULL OR p_lifecycle_status = '' OR a.lifecycle_status = p_lifecycle_status)
    ORDER BY a.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_assets_soft_delete` (IN `p_id` INT, IN `p_deleted_by` INT, IN `p_deleted_by_username` VARCHAR(50), IN `p_reason` TEXT)   BEGIN
    INSERT INTO deleted_assets(
        asset_id, property_number, `description`, category_id, category_name,
        quantity, acquisition_date, unit_value, office_id, office_name,
        accountable_person_name, location, `condition`, lifecycle_status,
        qr_code_path, sha256_hash, remarks,
        original_created_at, original_updated_at,
        deleted_by_user_id, deleted_by_username, delete_reason, deleted_at,
        asset_condition
    )
    SELECT a.asset_id, a.property_number, a.`description`, a.category_id, c.category_name,
           a.quantity, a.acquisition_date, a.unit_value, a.office_id, o.office_name,
           a.accountable_person, a.location, a.`condition`, a.lifecycle_status,
           a.qr_code_path, a.sha256_hash, a.remarks,
           a.created_at, a.updated_at,
           p_deleted_by, p_deleted_by_username, p_reason, NOW(),
           a.`condition`
    FROM assets a
    LEFT JOIN categories c ON a.category_id = c.category_id
    LEFT JOIN offices o ON a.office_id = o.office_id
    WHERE a.asset_id = p_id;

    UPDATE assets
    SET is_deleted = TRUE, deleted_at = NOW(), deleted_by = p_deleted_by, delete_reason = p_reason
    WHERE asset_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_assets_update` (IN `p_id` INT, IN `p_property_number` VARCHAR(50), IN `p_description` VARCHAR(255), IN `p_category_id` INT, IN `p_quantity` INT, IN `p_acquisition_date` DATE, IN `p_unit_value` DECIMAL(12,2), IN `p_office_id` INT, IN `p_accountable_person` VARCHAR(150), IN `p_physical_count` INT, IN `p_location` VARCHAR(150), IN `p_condition` VARCHAR(20), IN `p_lifecycle_status` VARCHAR(30), IN `p_qr_code_path` VARCHAR(255), IN `p_sha256_hash` VARCHAR(64), IN `p_remarks` TEXT)   BEGIN
    UPDATE assets SET
        property_number = p_property_number, `description` = p_description,
        category_id = p_category_id, quantity = p_quantity,
        acquisition_date = p_acquisition_date, unit_value = p_unit_value,
        office_id = p_office_id, accountable_person = p_accountable_person,
        physical_count = p_physical_count,
        location = p_location, `condition` = p_condition,
        lifecycle_status = p_lifecycle_status,
        qr_code_path = NULLIF(p_qr_code_path, ''), sha256_hash = NULLIF(p_sha256_hash, ''),
        remarks = NULLIF(p_remarks, ''), updated_at = NOW()
    WHERE asset_id = p_id AND is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_assets_update_lifecycle` (IN `p_id` INT, IN `p_lifecycle_status` VARCHAR(30))   BEGIN
    UPDATE assets SET lifecycle_status = p_lifecycle_status, updated_at = NOW()
    WHERE asset_id = p_id AND is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_assets_update_office` (IN `p_id` INT, IN `p_office_id` INT)   BEGIN
    UPDATE assets SET office_id = p_office_id, updated_at = NOW()
    WHERE asset_id = p_id AND is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_asset_history_create` (IN `p_asset_id` INT, IN `p_event_type` VARCHAR(30), IN `p_from_office_id` INT, IN `p_to_office_id` INT, IN `p_performed_by` INT, IN `p_notes` TEXT, OUT `p_id` INT)   BEGIN
    INSERT INTO asset_history(asset_id, event_type, from_office_id, to_office_id, performed_by, event_date, notes)
    VALUES(p_asset_id, p_event_type, NULLIF(p_from_office_id, 0), NULLIF(p_to_office_id, 0),
           p_performed_by, NOW(), NULLIF(p_notes, ''));
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_asset_history_get_all` ()   BEGIN
    SELECT h.history_id AS id, h.event_type AS eventType, h.event_date AS eventDate, h.notes,
           a.asset_id AS asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           u.user_id AS pb_id, u.username AS pb_username, u.full_name AS pb_fullName,
           fo.office_id AS fo_id, fo.office_name AS fo_officeName,
           too.office_id AS too_id, too.office_name AS too_officeName
    FROM asset_history h
    LEFT JOIN assets a ON h.asset_id = a.asset_id
    LEFT JOIN users u ON h.performed_by = u.user_id
    LEFT JOIN offices fo ON h.from_office_id = fo.office_id
    LEFT JOIN offices too ON h.to_office_id = too.office_id
    ORDER BY h.event_date DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_asset_history_get_by_asset` (IN `p_asset_id` INT)   BEGIN
    SELECT h.history_id AS id, h.event_type AS eventType, h.event_date AS eventDate, h.notes,
           a.asset_id AS asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           u.user_id AS pb_id, u.username AS pb_username, u.full_name AS pb_fullName,
           fo.office_id AS fo_id, fo.office_name AS fo_officeName,
           too.office_id AS too_id, too.office_name AS too_officeName
    FROM asset_history h
    LEFT JOIN assets a ON h.asset_id = a.asset_id
    LEFT JOIN users u ON h.performed_by = u.user_id
    LEFT JOIN offices fo ON h.from_office_id = fo.office_id
    LEFT JOIN offices too ON h.to_office_id = too.office_id
    WHERE h.asset_id = p_asset_id
    ORDER BY h.event_date DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_asset_history_search` (IN `p_search` VARCHAR(255))   BEGIN
    SET p_search = TRIM(p_search);
    SELECT h.history_id AS id, h.event_type AS eventType, h.event_date AS eventDate, h.notes,
           a.asset_id AS asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           u.user_id AS pb_id, u.username AS pb_username, u.full_name AS pb_fullName,
           fo.office_id AS fo_id, fo.office_name AS fo_officeName,
           too.office_id AS too_id, too.office_name AS too_officeName
    FROM asset_history h
    LEFT JOIN assets a ON h.asset_id = a.asset_id
    LEFT JOIN users u ON h.performed_by = u.user_id
    LEFT JOIN offices fo ON h.from_office_id = fo.office_id
    LEFT JOIN offices too ON h.to_office_id = too.office_id
    WHERE h.event_type LIKE CONCAT('%', p_search, '%')
       OR a.property_number LIKE CONCAT('%', p_search, '%')
       OR a.`description` LIKE CONCAT('%', p_search, '%')
       OR u.full_name LIKE CONCAT('%', p_search, '%')
       OR h.notes LIKE CONCAT('%', p_search, '%')
    ORDER BY h.event_date DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_audit_logs_create` (IN `p_user_id` INT, IN `p_action` VARCHAR(100), IN `p_module` VARCHAR(50), IN `p_target_id` INT, IN `p_target_type` VARCHAR(50), IN `p_details` TEXT, IN `p_ip_address` VARCHAR(45), OUT `p_id` INT)   BEGIN
    INSERT INTO audit_logs(user_id, action, module, target_id, target_type, details, ip_address, logged_at)
    VALUES(p_user_id, p_action, p_module, NULLIF(p_target_id, 0), NULLIF(p_target_type, ''),
           NULLIF(p_details, ''), NULLIF(p_ip_address, ''), NOW());
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_audit_logs_get_all` ()   BEGIN
    SELECT l.log_id AS id, l.action, l.module, l.target_id AS targetId,
           l.target_type AS targetType, l.details, l.ip_address AS ipAddress,
           l.logged_at AS loggedAt,
           u.user_id AS u_id, u.username AS u_username, u.full_name AS u_fullName
    FROM audit_logs l
    LEFT JOIN users u ON l.user_id = u.user_id
    ORDER BY l.logged_at DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_audit_logs_search` (IN `p_search` VARCHAR(255))   BEGIN
    SET p_search = TRIM(p_search);
    SELECT l.log_id AS id, l.action, l.module, l.target_id AS targetId,
           l.target_type AS targetType, l.details, l.ip_address AS ipAddress,
           l.logged_at AS loggedAt,
           u.user_id AS u_id, u.username AS u_username, u.full_name AS u_fullName
    FROM audit_logs l
    LEFT JOIN users u ON l.user_id = u.user_id
    WHERE l.action LIKE CONCAT('%', p_search, '%')
       OR l.module LIKE CONCAT('%', p_search, '%')
       OR l.details LIKE CONCAT('%', p_search, '%')
       OR u.username LIKE CONCAT('%', p_search, '%')
       OR u.full_name LIKE CONCAT('%', p_search, '%')
    ORDER BY l.logged_at DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_audit_log_digests_create` (IN `p_digest` TEXT, IN `p_covered_entries` INT, OUT `p_id` BIGINT)   BEGIN
    INSERT INTO audit_log_digests(digest, covered_entries, generated_at, generated_by_system)
    VALUES (p_digest, p_covered_entries, NOW(), TRUE);
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_audit_log_digests_get_latest` ()   BEGIN
    SELECT digest_id AS id, digest, covered_entries, generated_at, generated_by_system
    FROM audit_log_digests
    ORDER BY generated_at DESC
    LIMIT 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_auth_get_user_for_login` (IN `p_username` VARCHAR(50))   BEGIN
    SELECT u.user_id AS id, u.username, u.password_hash AS password,
           u.full_name AS fullName, u.`role`, u.is_active AS isActive,
           u.failed_login_attempts AS failedLoginAttempts,
           u.account_locked_until AS accountLockedUntil
    FROM users u
    WHERE LOWER(u.username) = LOWER(p_username);
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_auth_login_failure` (IN `p_user_id` INT, IN `p_max_attempts` INT, IN `p_lockout_minutes` INT)   BEGIN
    UPDATE users
    SET failed_login_attempts = failed_login_attempts + 1,
        account_locked_until = CASE
            WHEN failed_login_attempts + 1 >= p_max_attempts
                THEN DATE_ADD(NOW(), INTERVAL p_lockout_minutes MINUTE)
            ELSE account_locked_until
        END
    WHERE user_id = p_user_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_auth_login_success` (IN `p_user_id` INT)   BEGIN
    UPDATE users SET failed_login_attempts = 0, account_locked_until = NULL
    WHERE user_id = p_user_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_categories_create` (IN `p_name` VARCHAR(100), IN `p_description` TEXT, OUT `p_id` INT)   BEGIN
    INSERT INTO categories(category_name, `description`) VALUES(p_name, p_description);
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_categories_delete` (IN `p_id` INT)   BEGIN
    DELETE FROM categories WHERE category_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_categories_get_all` ()   BEGIN
    SELECT category_id AS id, category_name AS categoryName, `description`
    FROM categories ORDER BY category_name;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_categories_get_by_id` (IN `p_id` INT)   BEGIN
    SELECT category_id AS id, category_name AS categoryName, `description`
    FROM categories WHERE category_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_categories_name_exists` (IN `p_name` VARCHAR(100), OUT `p_exists` BOOLEAN)   BEGIN
    SELECT COUNT(*) > 0 INTO p_exists FROM categories
    WHERE LOWER(category_name) = LOWER(p_name);
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_categories_search` (IN `p_search` VARCHAR(255))   BEGIN
    SET p_search = TRIM(p_search);
    SELECT category_id AS id, category_name AS categoryName, `description`
    FROM categories
    WHERE category_name LIKE CONCAT('%', p_search, '%')
       OR `description` LIKE CONCAT('%', p_search, '%')
    ORDER BY category_name;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_categories_update` (IN `p_id` INT, IN `p_name` VARCHAR(100), IN `p_description` TEXT)   BEGIN
    UPDATE categories SET category_name = p_name, `description` = p_description
    WHERE category_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_devices_get_by_equipment` (IN `p_equipment_id` INT)   BEGIN
    SELECT device_id AS id, equipment_id AS equipmentId,
           item_code AS itemCode, serial_number AS serialNumber,
           model, amount_value AS amountValue, acquisition_date AS acquisitionDate,
           created_at AS createdAt, updated_at AS updatedAt
    FROM device_records
    WHERE equipment_id = p_equipment_id
    ORDER BY device_id ASC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_device_add` (IN `p_equipment_id` INT, IN `p_item_code` VARCHAR(50), IN `p_serial_number` VARCHAR(100), IN `p_model` VARCHAR(100), IN `p_amount_value` DECIMAL(12,2), IN `p_acquisition_date` DATE, OUT `p_new_id` BIGINT)   BEGIN
    INSERT INTO device_records (equipment_id, item_code, serial_number, model, amount_value, acquisition_date)
    VALUES (p_equipment_id, p_item_code, p_serial_number, p_model, p_amount_value, p_acquisition_date);
    SET p_new_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_device_delete` (IN `p_device_id` INT)   BEGIN
    DELETE FROM device_records WHERE device_id = p_device_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_device_update` (IN `p_device_id` INT, IN `p_item_code` VARCHAR(50), IN `p_serial_number` VARCHAR(100), IN `p_model` VARCHAR(100), IN `p_amount_value` DECIMAL(12,2), IN `p_acquisition_date` DATE)   BEGIN
    UPDATE device_records
    SET item_code        = p_item_code,
        serial_number    = p_serial_number,
        model            = p_model,
        amount_value     = p_amount_value,
        acquisition_date = p_acquisition_date
    WHERE device_id = p_device_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_create` (IN `p_asset_id` INT, IN `p_reason` TEXT, IN `p_inspection_findings` TEXT, IN `p_recommended_method` VARCHAR(20), IN `p_disposal_status` VARCHAR(20), IN `p_inspection_date` DATE, IN `p_approved_by` VARCHAR(150), IN `p_recorded_by` INT, IN `p_appraised_value` DECIMAL(12,2), IN `p_or_number` VARCHAR(50), IN `p_amount` DECIMAL(12,2), OUT `p_id` INT)   BEGIN
    INSERT INTO disposal_ledger(
        asset_id, reason, inspection_findings, recommended_method,
        disposal_status, inspection_date, approved_by, recorded_by,
        appraised_value, or_number, amount,
        is_deleted, created_at
    ) VALUES(
        p_asset_id, p_reason, p_inspection_findings, p_recommended_method,
        p_disposal_status, p_inspection_date, NULLIF(p_approved_by, ''), NULLIF(p_recorded_by, 0),
        p_appraised_value, NULLIF(p_or_number, ''), p_amount,
        FALSE, NOW()
    );
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_delete_by_asset` (IN `p_asset_id` INT)   BEGIN
    UPDATE disposal_ledger
    SET is_deleted = TRUE, deleted_at = NOW()
    WHERE asset_id = p_asset_id AND is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_get_by_asset` (IN `p_asset_id` INT)   BEGIN
    SELECT d.disposal_id AS id, d.reason, d.inspection_findings AS inspectionFindings,
           d.recommended_method AS recommendedMethod, d.disposal_status AS disposalStatus,
           d.inspection_date AS inspectionDate, d.created_at AS createdAt,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           a.quantity AS asset_quantity, a.unit_value AS asset_unitValue,
           a.acquisition_date AS asset_acquisitionDate, a.`condition` AS asset_condition,
           r.user_id AS rb_id, r.username AS rb_username, r.full_name AS rb_fullName,
           d.approved_by AS approvedBy,
           d.appraised_value AS appraisedValue, d.or_number AS orNumber, d.amount AS amount
    FROM disposal_ledger d
    LEFT JOIN assets a ON d.asset_id = a.asset_id
    LEFT JOIN users r ON d.recorded_by = r.user_id
    WHERE d.asset_id = p_asset_id AND d.is_deleted = FALSE
    ORDER BY d.inspection_date DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_get_by_id` (IN `p_id` INT)   BEGIN
    SELECT d.disposal_id AS id, d.reason, d.inspection_findings AS inspectionFindings,
           d.recommended_method AS recommendedMethod, d.disposal_status AS disposalStatus,
           d.inspection_date AS inspectionDate, d.created_at AS createdAt,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           a.quantity AS asset_quantity, a.unit_value AS asset_unitValue,
           a.acquisition_date AS asset_acquisitionDate, a.`condition` AS asset_condition,
           r.user_id AS rb_id, r.username AS rb_username, r.full_name AS rb_fullName,
           d.approved_by AS approvedBy,
           d.appraised_value AS appraisedValue, d.or_number AS orNumber, d.amount AS amount
    FROM disposal_ledger d
    LEFT JOIN assets a ON d.asset_id = a.asset_id
    LEFT JOIN users r ON d.recorded_by = r.user_id
    WHERE d.disposal_id = p_id AND d.is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_justifications_create` (IN `p_disposal_id` BIGINT, IN `p_justification` TEXT, OUT `p_id` INT)   BEGIN
    INSERT INTO disposal_justifications(disposal_id, justification, generated_at, generated_by_system)
    VALUES (p_disposal_id, p_justification, NOW(), TRUE);
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_justifications_get_latest` (IN `p_disposal_id` BIGINT)   BEGIN
    SELECT justification_id AS id, disposal_id, justification, generated_at, generated_by_system
    FROM disposal_justifications
    WHERE disposal_id = p_disposal_id
    ORDER BY generated_at DESC
    LIMIT 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_list` (IN `p_search` VARCHAR(255), IN `p_limit` INT, IN `p_offset` INT, IN `p_recommended_method` VARCHAR(20), IN `p_disposal_status` VARCHAR(20))   BEGIN
    SET p_search = TRIM(p_search);
    SELECT d.disposal_id AS id, d.reason, d.inspection_findings AS inspectionFindings,
           d.recommended_method AS recommendedMethod, d.disposal_status AS disposalStatus,
           d.inspection_date AS inspectionDate, d.created_at AS createdAt,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           a.quantity AS asset_quantity, a.unit_value AS asset_unitValue,
           a.acquisition_date AS asset_acquisitionDate, a.`condition` AS asset_condition,
           r.user_id AS rb_id, r.username AS rb_username, r.full_name AS rb_fullName,
           d.approved_by AS approvedBy,
           d.appraised_value AS appraisedValue, d.or_number AS orNumber, d.amount AS amount
    FROM disposal_ledger d
    LEFT JOIN assets a ON d.asset_id = a.asset_id
    LEFT JOIN users r ON d.recorded_by = r.user_id
    WHERE d.is_deleted = FALSE
      AND (
        p_search IS NULL OR p_search = '' OR
        d.recommended_method LIKE CONCAT('%', p_search, '%')
        OR d.disposal_status LIKE CONCAT('%', p_search, '%')
        OR d.reason LIKE CONCAT('%', p_search, '%')
        OR a.property_number LIKE CONCAT('%', p_search, '%')
        OR a.`description` LIKE CONCAT('%', p_search, '%')
        OR r.full_name LIKE CONCAT('%', p_search, '%')
      )
      AND (p_recommended_method IS NULL OR p_recommended_method = '' OR d.recommended_method = p_recommended_method)
      AND (p_disposal_status IS NULL OR p_disposal_status = '' OR d.disposal_status = p_disposal_status)
    ORDER BY d.inspection_date DESC
    LIMIT p_limit OFFSET p_offset;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_soft_delete` (IN `p_id` INT, IN `p_deleted_by` INT, IN `p_deleted_by_username` VARCHAR(50), IN `p_reason` TEXT)   BEGIN
    INSERT INTO deleted_disposal(
        disposal_id, asset_id, property_number, asset_description,
        reason, inspection_findings, recommended_method,
        disposal_status, inspection_date,
        approved_by_user_id, approved_by_name,
        appraised_value, or_number, amount,
        recorded_by_user_id, recorded_by_name,
        original_created_at,
        deleted_by_user_id, deleted_by_username, delete_reason, deleted_at
    )
    SELECT d.disposal_id, d.asset_id, a.property_number, a.`description`,
           d.reason, d.inspection_findings, d.recommended_method,
           d.disposal_status, d.inspection_date,
           NULL, d.approved_by,
           d.appraised_value, d.or_number, d.amount,
           d.recorded_by, r.full_name,
           d.created_at,
           p_deleted_by, p_deleted_by_username, p_reason, NOW()
    FROM disposal_ledger d
    LEFT JOIN assets a ON d.asset_id = a.asset_id
    LEFT JOIN users r ON d.recorded_by = r.user_id
    WHERE d.disposal_id = p_id;

    UPDATE disposal_ledger
    SET is_deleted = TRUE, deleted_at = NOW(), deleted_by = p_deleted_by, delete_reason = p_reason
    WHERE disposal_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disposal_update` (IN `p_id` INT, IN `p_reason` TEXT, IN `p_inspection_findings` TEXT, IN `p_recommended_method` VARCHAR(20), IN `p_disposal_status` VARCHAR(20), IN `p_inspection_date` DATE, IN `p_approved_by` VARCHAR(150), IN `p_appraised_value` DECIMAL(12,2), IN `p_or_number` VARCHAR(50), IN `p_amount` DECIMAL(12,2))   BEGIN
    UPDATE disposal_ledger SET
        reason = p_reason, inspection_findings = p_inspection_findings,
        recommended_method = p_recommended_method, disposal_status = p_disposal_status,
        inspection_date = p_inspection_date, approved_by = NULLIF(p_approved_by, ''),
        appraised_value = p_appraised_value, or_number = NULLIF(p_or_number, ''), amount = p_amount
    WHERE disposal_id = p_id AND is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_equipment_create` (IN `p_type` VARCHAR(50), IN `p_equipment_type` VARCHAR(100), IN `p_item_code` VARCHAR(50), IN `p_article` VARCHAR(255), IN `p_office` VARCHAR(255), IN `p_location` VARCHAR(255), IN `p_description` TEXT, IN `p_accountable_person` VARCHAR(150), IN `p_accountable_person_phone` VARCHAR(50), IN `p_accountable_person_email` VARCHAR(150), IN `p_device_count` INT, OUT `p_new_id` BIGINT)   BEGIN
    INSERT INTO equipment_records (
        type, equipment_type, item_code, article, office, location, description,
        accountable_person, accountable_person_phone, accountable_person_email, device_count
    ) VALUES (
        p_type, p_equipment_type, p_item_code, p_article, p_office, p_location, p_description,
        p_accountable_person, p_accountable_person_phone, p_accountable_person_email,
        COALESCE(p_device_count, 0)
    );
    SET p_new_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_equipment_delete` (IN `p_id` INT)   BEGIN
    DELETE FROM equipment_records WHERE equipment_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_equipment_get_by_id` (IN `p_id` INT)   BEGIN
    SELECT equipment_id AS id, type, equipment_type AS equipmentType,
           item_code AS itemCode, article, office, location, description,
           accountable_person AS accountablePerson,
           accountable_person_phone AS accountablePersonPhone,
           accountable_person_email AS accountablePersonEmail,
           device_count AS deviceCount,
           created_at AS createdAt, updated_at AS updatedAt
    FROM equipment_records
    WHERE equipment_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_equipment_list` (IN `p_search` VARCHAR(255), IN `p_limit` INT, IN `p_offset` INT)   BEGIN
    SET p_search = TRIM(p_search);
    SELECT equipment_id AS id, type, equipment_type AS equipmentType,
           item_code AS itemCode, article, office, location, description,
           accountable_person AS accountablePerson,
           accountable_person_phone AS accountablePersonPhone,
           accountable_person_email AS accountablePersonEmail,
           device_count AS deviceCount,
           created_at AS createdAt, updated_at AS updatedAt
    FROM equipment_records
    WHERE (
        p_search IS NULL OR p_search = '' OR
        item_code LIKE CONCAT('%', p_search, '%')
        OR article LIKE CONCAT('%', p_search, '%')
        OR equipment_type LIKE CONCAT('%', p_search, '%')
        OR office LIKE CONCAT('%', p_search, '%')
        OR location LIKE CONCAT('%', p_search, '%')
        OR description LIKE CONCAT('%', p_search, '%')
        OR accountable_person LIKE CONCAT('%', p_search, '%')
      )
    ORDER BY created_at DESC
    LIMIT p_limit OFFSET p_offset;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_equipment_update` (IN `p_id` INT, IN `p_type` VARCHAR(50), IN `p_equipment_type` VARCHAR(100), IN `p_item_code` VARCHAR(50), IN `p_article` VARCHAR(255), IN `p_office` VARCHAR(255), IN `p_location` VARCHAR(255), IN `p_description` TEXT, IN `p_accountable_person` VARCHAR(150), IN `p_accountable_person_phone` VARCHAR(50), IN `p_accountable_person_email` VARCHAR(150), IN `p_device_count` INT)   BEGIN
    UPDATE equipment_records
    SET type                     = p_type,
        equipment_type           = p_equipment_type,
        item_code                = p_item_code,
        article                  = p_article,
        office                   = p_office,
        location                 = p_location,
        description              = p_description,
        accountable_person       = p_accountable_person,
        accountable_person_phone = p_accountable_person_phone,
        accountable_person_email = p_accountable_person_email,
        device_count             = COALESCE(p_device_count, 0)
    WHERE equipment_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_create` (IN `p_asset_id` INT, IN `p_maintenance_type` VARCHAR(20), IN `p_findings` TEXT, IN `p_actions_taken` TEXT, IN `p_assigned_to` VARCHAR(150), IN `p_maintenance_date` DATE, IN `p_cost` DECIMAL(10,2), IN `p_status` VARCHAR(20), IN `p_recorded_by` INT, OUT `p_id` INT)   BEGIN
    INSERT INTO maintenance_ledger(
        asset_id, maintenance_type, findings, actions_taken, assigned_to,
        maintenance_date, cost, `status`, recorded_by, is_deleted, created_at
    ) VALUES(
        p_asset_id, p_maintenance_type, p_findings, p_actions_taken, NULLIF(p_assigned_to, ''),
        p_maintenance_date, p_cost, p_status, NULLIF(p_recorded_by, 0), FALSE, NOW()
    );
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_delete_by_asset` (IN `p_asset_id` INT)   BEGIN
    UPDATE maintenance_ledger
    SET is_deleted = TRUE, deleted_at = NOW()
    WHERE asset_id = p_asset_id AND is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_get_by_asset` (IN `p_asset_id` INT)   BEGIN
    SELECT m.maintenance_id AS id, m.maintenance_type AS maintenanceType,
           m.findings, m.actions_taken AS actionsTaken,
           m.maintenance_date AS maintenanceDate, m.cost, m.`status`, m.created_at AS createdAt,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           r.user_id AS rb_id, r.username AS rb_username, r.full_name AS rb_fullName,
           m.assigned_to AS assignedTo
    FROM maintenance_ledger m
    LEFT JOIN assets a ON m.asset_id = a.asset_id
    LEFT JOIN users r ON m.recorded_by = r.user_id
    WHERE m.asset_id = p_asset_id AND m.is_deleted = FALSE
    ORDER BY m.maintenance_date DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_get_by_id` (IN `p_id` INT)   BEGIN
    SELECT m.maintenance_id AS id, m.maintenance_type AS maintenanceType,
           m.findings, m.actions_taken AS actionsTaken,
           m.maintenance_date AS maintenanceDate, m.cost, m.`status`, m.created_at AS createdAt,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           r.user_id AS rb_id, r.username AS rb_username, r.full_name AS rb_fullName,
           m.assigned_to AS assignedTo
    FROM maintenance_ledger m
    LEFT JOIN assets a ON m.asset_id = a.asset_id
    LEFT JOIN users r ON m.recorded_by = r.user_id
    WHERE m.maintenance_id = p_id AND m.is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_list` (IN `p_search` VARCHAR(255), IN `p_limit` INT, IN `p_offset` INT, IN `p_maintenance_type` VARCHAR(20), IN `p_status` VARCHAR(20))   BEGIN
    SET p_search = TRIM(p_search);
    SELECT m.maintenance_id AS id, m.maintenance_type AS maintenanceType,
           m.findings, m.actions_taken AS actionsTaken,
           m.maintenance_date AS maintenanceDate, m.cost, m.`status`, m.created_at AS createdAt,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           r.user_id AS rb_id, r.username AS rb_username, r.full_name AS rb_fullName,
           m.assigned_to AS assignedTo
    FROM maintenance_ledger m
    LEFT JOIN assets a ON m.asset_id = a.asset_id
    LEFT JOIN users r ON m.recorded_by = r.user_id
    WHERE m.is_deleted = FALSE
      AND (
        p_search IS NULL OR p_search = '' OR
        m.maintenance_type LIKE CONCAT('%', p_search, '%')
        OR m.findings LIKE CONCAT('%', p_search, '%')
        OR m.`status` LIKE CONCAT('%', p_search, '%')
        OR a.property_number LIKE CONCAT('%', p_search, '%')
        OR a.`description` LIKE CONCAT('%', p_search, '%')
        OR r.full_name LIKE CONCAT('%', p_search, '%')
      )
      AND (p_maintenance_type IS NULL OR p_maintenance_type = '' OR m.maintenance_type = p_maintenance_type)
      AND (p_status IS NULL OR p_status = '' OR m.`status` = p_status)
    ORDER BY m.maintenance_date DESC
    LIMIT p_limit OFFSET p_offset;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_soft_delete` (IN `p_id` INT, IN `p_deleted_by` INT, IN `p_deleted_by_username` VARCHAR(50), IN `p_reason` TEXT)   BEGIN
    INSERT INTO deleted_maintenance(
        maintenance_id, asset_id, property_number, asset_description,
        maintenance_type, findings, actions_taken,
        assigned_to_user_id, assigned_to_name,
        maintenance_date, cost, `status`,
        recorded_by_user_id, recorded_by_name,
        original_created_at,
        deleted_by_user_id, deleted_by_username, delete_reason, deleted_at
    )
    SELECT m.maintenance_id, m.asset_id, a.property_number, a.`description`,
           m.maintenance_type, m.findings, m.actions_taken,
           NULL, m.assigned_to,
           m.maintenance_date, m.cost, m.`status`,
           m.recorded_by, r.full_name,
           m.created_at,
           p_deleted_by, p_deleted_by_username, p_reason, NOW()
    FROM maintenance_ledger m
    LEFT JOIN assets a ON m.asset_id = a.asset_id
    LEFT JOIN users r ON m.recorded_by = r.user_id
    WHERE m.maintenance_id = p_id;

    UPDATE maintenance_ledger
    SET is_deleted = TRUE, deleted_at = NOW(), deleted_by = p_deleted_by, delete_reason = p_reason
    WHERE maintenance_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_summaries_create` (IN `p_maintenance_id` BIGINT, IN `p_summary` TEXT, OUT `p_id` BIGINT)   BEGIN
    INSERT INTO maintenance_summaries(maintenance_id, summary, generated_at, generated_by_system)
    VALUES (p_maintenance_id, p_summary, NOW(), TRUE);
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_summaries_get_latest` (IN `p_maintenance_id` BIGINT)   BEGIN
    SELECT summary_id AS id, maintenance_id, summary, generated_at, generated_by_system
    FROM maintenance_summaries
    WHERE maintenance_id = p_maintenance_id
    ORDER BY generated_at DESC
    LIMIT 1;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_maintenance_update` (IN `p_id` INT, IN `p_maintenance_type` VARCHAR(20), IN `p_findings` TEXT, IN `p_actions_taken` TEXT, IN `p_assigned_to` VARCHAR(150), IN `p_maintenance_date` DATE, IN `p_cost` DECIMAL(10,2), IN `p_status` VARCHAR(20))   BEGIN
    UPDATE maintenance_ledger SET
        maintenance_type = p_maintenance_type, findings = p_findings,
        actions_taken = p_actions_taken, assigned_to = NULLIF(p_assigned_to, ''),
        maintenance_date = p_maintenance_date, cost = p_cost, `status` = p_status
    WHERE maintenance_id = p_id AND is_deleted = FALSE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_offices_create` (IN `p_name` VARCHAR(100), IN `p_head_user_id` INT, OUT `p_id` INT)   BEGIN
    INSERT INTO offices(office_name, head_user_id, created_at)
    VALUES(p_name, NULLIF(p_head_user_id, 0), NOW());
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_offices_delete` (IN `p_id` INT)   BEGIN
    DELETE FROM offices WHERE office_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_offices_get_all` ()   BEGIN
    SELECT o.office_id AS id, o.office_name AS officeName, o.created_at AS createdAt,
           u.user_id AS hu_id, u.username AS hu_username, u.full_name AS hu_fullName
    FROM offices o
    LEFT JOIN users u ON o.head_user_id = u.user_id
    ORDER BY o.office_name;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_offices_get_by_id` (IN `p_id` INT)   BEGIN
    SELECT o.office_id AS id, o.office_name AS officeName, o.created_at AS createdAt,
           u.user_id AS hu_id, u.username AS hu_username, u.full_name AS hu_fullName
    FROM offices o
    LEFT JOIN users u ON o.head_user_id = u.user_id
    WHERE o.office_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_offices_search` (IN `p_search` VARCHAR(255))   BEGIN
    SET p_search = TRIM(p_search);
    SELECT o.office_id AS id, o.office_name AS officeName, o.created_at AS createdAt,
           u.user_id AS hu_id, u.username AS hu_username, u.full_name AS hu_fullName
    FROM offices o
    LEFT JOIN users u ON o.head_user_id = u.user_id
    WHERE o.office_name LIKE CONCAT('%', p_search, '%')
    ORDER BY o.office_name;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_offices_update` (IN `p_id` INT, IN `p_name` VARCHAR(100), IN `p_head_user_id` INT)   BEGIN
    UPDATE offices
    SET office_name = p_name, head_user_id = NULLIF(p_head_user_id, 0)
    WHERE office_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_change_password` (IN `p_id` INT, IN `p_password_hash` VARCHAR(255))   BEGIN
    UPDATE users SET password_hash = p_password_hash WHERE user_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_create` (IN `p_username` VARCHAR(50), IN `p_email` VARCHAR(255), IN `p_password_hash` VARCHAR(255), IN `p_full_name` VARCHAR(100), IN `p_role` VARCHAR(20), IN `p_office_id` INT, IN `p_is_active` BOOLEAN, OUT `p_id` INT)   BEGIN
    INSERT INTO users(username, email, password_hash, full_name, `role`, office_id, is_active, created_at, token_version)
    VALUES(p_username, NULLIF(p_email, ''), p_password_hash, p_full_name, p_role, NULLIF(p_office_id, 0), p_is_active, NOW(), 0);
    SET p_id = LAST_INSERT_ID();
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_delete` (IN `p_id` INT)   BEGIN
    DELETE FROM users WHERE user_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_get_all` ()   BEGIN
    SELECT u.user_id AS id, u.username, u.full_name AS fullName, u.`role`,
           u.is_active AS isActive, u.created_at AS createdAt,
           o.office_id AS office_id, o.office_name AS office_officeName
    FROM users u
    LEFT JOIN offices o ON u.office_id = o.office_id
    ORDER BY u.full_name;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_get_by_id` (IN `p_id` INT)   BEGIN
    SELECT u.user_id AS id, u.username, u.full_name AS fullName, u.`role`,
           u.is_active AS isActive, u.created_at AS createdAt,
           o.office_id AS office_id, o.office_name AS office_officeName
    FROM users u
    LEFT JOIN offices o ON u.office_id = o.office_id
    WHERE u.user_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_get_by_username` (IN `p_username` VARCHAR(50))   BEGIN
    SELECT u.user_id AS id, u.username, u.password_hash AS password,
           u.full_name AS fullName, u.`role`, u.is_active AS isActive,
           u.failed_login_attempts AS failedLoginAttempts,
           u.account_locked_until AS accountLockedUntil,
           u.created_at AS createdAt,
           o.office_id AS office_id, o.office_name AS office_officeName
    FROM users u
    LEFT JOIN offices o ON u.office_id = o.office_id
    WHERE LOWER(u.username) = LOWER(p_username);
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_search` (IN `p_search` VARCHAR(255))   BEGIN
    SET p_search = TRIM(p_search);
    SELECT u.user_id AS id, u.username, u.full_name AS fullName, u.`role`,
           u.is_active AS isActive, u.created_at AS createdAt,
           o.office_id AS office_id, o.office_name AS office_officeName
    FROM users u
    LEFT JOIN offices o ON u.office_id = o.office_id
    WHERE u.username LIKE CONCAT('%', p_search, '%')
       OR u.full_name LIKE CONCAT('%', p_search, '%')
       OR u.`role` LIKE CONCAT('%', p_search, '%')
       OR o.office_name LIKE CONCAT('%', p_search, '%')
    ORDER BY u.full_name;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_update` (IN `p_id` INT, IN `p_full_name` VARCHAR(100), IN `p_role` VARCHAR(20), IN `p_office_id` INT, IN `p_is_active` BOOLEAN, IN `p_password_hash` VARCHAR(255))   BEGIN
    UPDATE users
    SET full_name = p_full_name,
        `role` = p_role,
        office_id = NULLIF(p_office_id, 0),
        is_active = p_is_active,
        password_hash = IF(p_password_hash IS NULL OR p_password_hash = '', password_hash, p_password_hash)
    WHERE user_id = p_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_users_username_exists` (IN `p_username` VARCHAR(50), OUT `p_exists` BOOLEAN)   BEGIN
    SELECT COUNT(*) > 0 INTO p_exists FROM users
    WHERE LOWER(username) = LOWER(p_username);
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `ai_recommendations`
--

CREATE TABLE `ai_recommendations` (
  `recommendation_id` bigint(20) NOT NULL,
  `asset_id` int(11) NOT NULL,
  `asset_age_years` decimal(5,2) NOT NULL COMMENT 'Computed age of the asset in years',
  `total_repair_cost` decimal(12,2) NOT NULL COMMENT 'Cumulative repair costs from maintenance ledger',
  `repair_frequency` int(11) NOT NULL COMMENT 'Count of REPAIR-type maintenance events',
  `condition_score` int(11) NOT NULL COMMENT '1=Unserviceable, 2=Repairable, 3=Serviceable',
  `recommendation` enum('MAINTAIN','REPAIR','MONITOR','REVIEW_FOR_DISPOSAL','BUDGET_PRIORITY') NOT NULL,
  `rationale` text NOT NULL COMMENT 'Explanation based on rule evaluation',
  `generated_at` datetime NOT NULL DEFAULT current_timestamp(),
  `generated_by_system` tinyint(1) NOT NULL DEFAULT 1 COMMENT 'TRUE = auto-generated; FALSE = manually triggered'
) ;

--
-- Dumping data for table `ai_recommendations`
--

INSERT INTO `ai_recommendations` (`recommendation_id`, `asset_id`, `asset_age_years`, `total_repair_cost`, `repair_frequency`, `condition_score`, `recommendation`, `rationale`, `generated_at`, `generated_by_system`) VALUES
(1, 2, 0.46, 0.00, 0, 3, 'MONITOR', 'This laptop is very new and currently in excellent condition. It is important to monitor its performance and usage closely over time, as it is a valuable asset to the office. Regularly observe its operation to ensure it continues to function effectively and to track any emerging needs.', '2026-07-03 12:39:59', 1),
(2, 2, 0.46, 0.00, 0, 3, 'MONITOR', 'This laptop is very new, less than half a year old, and is currently in excellent, serviceable condition. With no recorded repair history or costs, it is performing as expected. Continue to observe its performance and ensure it remains in good working order.', '2026-07-03 16:06:55', 1),
(3, 2, 0.46, 0.00, 0, 3, 'MAINTAIN', 'This laptop is very new and currently in excellent working condition. We recommend establishing a routine schedule for cleaning and software updates to keep it operating smoothly. Proactive care will help ensure its long-term reliability and performance.', '2026-07-03 17:58:14', 1),
(4, 25, 0.47, 0.00, 0, 3, 'MAINTAIN', 'This laptop is very new and currently in excellent working condition. Regular care and preventative measures are important to keep it performing well. Please ensure it undergoes routine checks and is kept clean to maintain its current excellent state.', '2026-07-05 20:27:00', 1),
(5, 23, 0.47, 0.00, 0, 3, 'MAINTAIN', 'This laptop is very new and in excellent working condition. To keep it performing optimally and extend its lifespan, ensure it receives regular cleaning, software updates, and basic preventative care. This proactive approach will help avoid future issues and maintain its efficiency for your office\'s needs.', '2026-07-05 21:17:10', 1),
(6, 3, 0.45, 0.00, 0, 3, 'MAINTAIN', 'This printer is very new and currently in excellent, serviceable condition. Regular cleaning and routine checks will help ensure it continues to operate efficiently. Continue with standard care to maximize its lifespan and prevent future issues.', '2026-07-05 22:41:45', 1),
(7, 2, 0.47, 0.00, 0, 1, 'REVIEW_FOR_DISPOSAL', 'This asset, a high-value laptop less than a year old, is recorded as unserviceable and already disposed without any repair history. It is highly unusual for such a new item to be disposed so quickly. Please investigate the circumstances of its early disposal and the lack of repair records to ensure proper procedures were followed for this valuable equipment.', '2026-07-05 22:51:33', 1);

-- --------------------------------------------------------

--
-- Table structure for table `assets`
--

CREATE TABLE `assets` (
  `asset_id` int(11) NOT NULL,
  `property_number` varchar(50) NOT NULL COMMENT 'Official COA-assigned property number',
  `description` varchar(255) NOT NULL COMMENT 'Article / equipment description',
  `category_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL DEFAULT 1,
  `acquisition_date` date NOT NULL,
  `unit_value` decimal(12,2) NOT NULL COMMENT 'Acquisition unit value in PHP',
  `office_id` int(11) NOT NULL COMMENT 'Currently assigned office / location',
  `accountable_person` varchar(150) DEFAULT NULL COMMENT 'Name of person accountable for this asset',
  `physical_count` int(11) DEFAULT NULL COMMENT 'Actual count during physical inventory; NULL if not yet counted',
  `location` varchar(150) NOT NULL COMMENT 'Physical location of the asset',
  `condition` enum('SERVICEABLE','REPAIRABLE','UNSERVICEABLE') NOT NULL,
  `lifecycle_status` enum('REGISTERED','ASSIGNED','TRANSFERRED','UNDER_MAINTENANCE','DISPOSED','ARCHIVED') NOT NULL,
  `qr_code_path` varchar(255) DEFAULT NULL COMMENT 'File path or URL of QR code image (ZXing)',
  `sha256_hash` varchar(64) DEFAULT NULL COMMENT '64-char hex hash for tamper detection',
  `remarks` text DEFAULT NULL,
  `is_deleted` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'Soft delete flag; TRUE = record is deleted but retained in table',
  `deleted_at` datetime DEFAULT NULL COMMENT 'Timestamp when the record was soft-deleted',
  `deleted_by` int(11) DEFAULT NULL COMMENT 'User who performed the soft delete (ref: users)',
  `delete_reason` text DEFAULT NULL COMMENT 'Reason provided by the user when deleting the record',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `assets`
--

INSERT INTO `assets` (`asset_id`, `property_number`, `description`, `category_id`, `quantity`, `acquisition_date`, `unit_value`, `office_id`, `accountable_person`, `physical_count`, `location`, `condition`, `lifecycle_status`, `qr_code_path`, `sha256_hash`, `remarks`, `is_deleted`, `deleted_at`, `deleted_by`, `delete_reason`, `created_at`, `updated_at`) VALUES
(1,'COA-2026-001','Dell Latitude 5440 Laptop',1,1,'2026-01-15',45000.00,1,'Juan Dela Cruz',1,'GSO Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Assigned to IT division',0,NULL,NULL,NULL,'2026-06-30 10:16:33','2026-07-19 08:29:40'),
(2,'COA-2026-002','Dell Latitude 5440 Laptop',2,1,'2026-01-15',52000.00,16,'Juan Dela Cruz',1,'Information and Communications Technology Office','UNSERVICEABLE','DISPOSED',NULL,NULL,'Assigned to ICT support staff',0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-19 11:32:42'),
(3,'COA-2026-003','HP LaserJet Pro M404dn Printer',2,1,'2026-01-20',18500.00,6,'Maria Santos',1,'Accounting Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(4,'COA-2026-004','Executive Office Desk',3,1,'2025-11-05',9500.00,1,'Hon. Mayor',1,'Office of the Mayor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-03 08:37:25'),
(5,'COA-2026-005','4-Drawer Steel Filing Cabinet',3,3,'2025-10-12',6200.00,8,NULL,3,'Assessor\'s Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(6,'COA-2026-006','Canon imageRUNNER 2625i Photocopier',4,1,'2025-09-01',95000.00,9,NULL,1,'Civil Registrar\'s Office','SERVICEABLE','ASSIGNED',NULL,NULL,'Shared unit for records division',0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(7,'COA-2026-007','Toyota Hilux Service Pickup',5,1,'2024-06-18',1250000.00,17,'Pedro Ramos',1,'Disaster Risk Reduction and Management Office','SERVICEABLE','ASSIGNED',NULL,NULL,'Plate No. SJH-1234',0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-03 08:37:25'),
(8,'COA-2026-008','Split-Type Air Conditioner 2HP',1,1,'2025-08-22',38000.00,15,NULL,1,'General Services Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(9,'COA-2026-009','Epson EB-X49 Projector',2,1,'2025-07-30',32000.00,4,NULL,1,'Human Resource Management Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(10,'COA-2026-010','Ergonomic Office Chair',3,10,'2025-05-14',4500.00,11,NULL,9,'Municipal Planning and Development Office','SERVICEABLE','ASSIGNED',NULL,NULL,'Bulk purchase of 10 units',0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(11,'COA-2026-011','Refrigerator 7 cu.ft.',1,1,'2024-03-10',16500.00,12,NULL,1,'Municipal Health Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(12,'COA-2026-012','Acer Veriton Desktop Computer Set',2,5,'2025-02-25',34000.00,14,NULL,4,'Municipal Agriculture Office','SERVICEABLE','ASSIGNED',NULL,NULL,'Set includes monitor, keyboard, mouse',0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(13,'COA-2026-013','Yamaha Brush Cutter',4,2,'2025-04-02',12500.00,10,'Roberto Cruz',2,'Municipal Engineering Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-03 08:37:25'),
(14,'COA-2026-014','Honda Generator 5.5kVA',4,1,'2024-12-19',68000.00,13,NULL,1,'Municipal Social Welfare and Development Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(15,'COA-2026-015','Conference Table 10-Seater',3,1,'2025-01-08',22000.00,2,NULL,1,'Office of the Vice Mayor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(16,'COA-2026-016','Wireless Microphone System',2,1,'2025-06-11',14500.00,3,NULL,1,'Sangguniang Bayan Office','SERVICEABLE','ASSIGNED',NULL,NULL,'Used for session hall',0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(17,'COA-2026-017','Cash Counting Machine',4,1,'2025-03-27',27500.00,7,'Elena Fernandez',1,'Treasury Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-03 08:37:25'),
(18,'COA-2026-018','TP-Link 24-Port Network Switch',2,2,'2025-09-15',8200.00,16,NULL,2,'Information and Communications Technology Office','SERVICEABLE','ASSIGNED',NULL,NULL,'Server room rack unit',0,NULL,NULL,NULL,'2026-07-03 08:37:25','2026-07-20 14:59:08'),
(23,'TEST-DEBUG-003','Dell Latitude 5440 Laptop',1,1,'2026-01-15',45000.00,1,'Juan Dela Cruz',1,'GSO Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Brand new unit',0,NULL,NULL,NULL,'2026-07-05 15:18:15','2026-07-20 14:59:08'),
(25,'COA-2026-019','Dell Latitude 5440 Laptop',1,1,'2026-01-15',45000.00,1,'Juan Dela Cruz',1,'Office of the Mayor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Brand new unit',0,NULL,NULL,NULL,'2026-07-05 15:32:13','2026-07-20 07:07:23'),
(27,'COA-2022-263','Testing',2,1,'2026-07-09',24000.00,12,'Dr. Jose Rizal',1,'Municipal Health Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-20 07:25:36','2026-07-20 07:25:36'),
(28,'COA-2026-020','Toyota Innova',5,1,'2026-07-14',5000000.00,2,'Vico Sotto',1,'Office of the Vice Mayor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-20 07:57:40','2026-07-20 08:18:32'),
(29,'COA-2026-021','Test Bulk Item A',1,2,'2026-01-10',1500.50,1,'Test Person',2,'Test Room','SERVICEABLE','ASSIGNED',NULL,NULL,'bulk test',1,'2026-07-20 09:19:48',2,NULL,'2026-07-20 09:19:20','2026-07-20 09:19:48'),
(30,'COA-2026-022','Ineffa',5,1,'2026-07-10',50000.00,17,'Aino',1,'Disaster Risk Reduction and Management Office','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-07-20 09:45:46','2026-07-20 09:45:46'),
(31,'COA-2023-001','Toyota Hiace',5,1,'2023-07-12',2100000.00,12,'Ocean Frank',1,'Municipal Health Office','SERVICEABLE','ASSIGNED',NULL,NULL,'Transport Vehicle',0,NULL,NULL,NULL,'2026-07-14 10:57:42','2026-07-14 12:19:41'),
(32,'COA-2024-001','Wireless Router',2,1,'2024-04-25',26101.56,1,'Ana Del Rosario',1,'Office of the Mayor - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-04-25 09:00:00','2026-07-17 18:12:48'),
(33,'COA-2022-001','Rice Thresher',9,5,'2022-04-17',77545.25,1,'Ramon Dela Cruz',5,'Office of the Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2022-04-18 09:00:00','2026-07-17 18:12:48'),
(34,'COA-2022-002','Bulldozer',6,1,'2022-10-08',2650315.58,12,'Cecilia Bautista',NULL,'Municipal Health Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-10-08 09:00:00','2026-07-17 18:12:48'),
(35,'COA-2023-002','Backhoe Loader',6,1,'2023-11-25',480599.49,7,'Luz Santos',1,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-27 09:00:00','2026-07-17 18:12:48'),
(36,'COA-2022-003','Dump Truck',5,1,'2022-10-31',749492.63,3,'Rosa Pascual',1,'Sangguniang Bayan Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-31 09:00:00','2026-07-20 14:59:08'),
(37,'COA-2025-001','Electric Fan (Stand Type)',1,1,'2025-03-20',44764.90,8,'Jose Torres',NULL,'Assessor\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-20 09:00:00','2026-07-17 18:12:48'),
(38,'COA-2018-001','Dump Truck',5,1,'2018-10-07',1432394.23,5,'Eduardo Aguilar',1,'Budget Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2018-10-09 09:00:00','2026-07-20 14:59:08'),
(39,'COA-2024-002','Steel Locker Cabinet',3,5,'2024-11-18',2902.54,6,'Francisco Rivera',5,'Accounting Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-20 09:00:00','2026-07-20 14:59:08'),
(40,'COA-2017-001','Multi-Purpose Van',5,1,'2017-04-01',1210839.19,11,'Norma Ocampo',1,'Municipal Planning and Development Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-04 09:00:00','2026-07-20 14:59:08'),
(41,'COA-2017-002','Water Pump (Irrigation)',9,1,'2017-09-18',98700.40,7,'Ricardo Dela Cruz',NULL,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-18 09:00:00','2026-07-20 14:59:08'),
(42,'COA-2025-002','Refrigerator (2-Door)',1,1,'2025-11-05',6996.81,8,'Jose Gonzales',NULL,'Assessor\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-05 09:00:00','2026-07-17 18:12:48'),
(43,'COA-2023-003','Binding Machine',4,1,'2023-12-30',27737.52,7,'Carmen Pascual',1,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2023-12-31 09:00:00','2026-07-20 14:59:08'),
(44,'COA-2017-003','Handheld Two-Way Radio',7,1,'2017-01-21',30506.77,7,'Teresa Pascual',1,'Treasury Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-23 09:00:00','2026-07-20 14:59:08'),
(45,'COA-2018-002','Bulletin Board (Cork, Framed)',4,1,'2018-02-18',11691.30,7,'Francisco Flores',NULL,'Treasury Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-19 09:00:00','2026-07-20 14:59:08'),
(46,'COA-2020-001','Bulletin Board (Cork, Framed)',4,1,'2020-07-22',32844.22,6,NULL,NULL,'Accounting Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-23 09:00:00','2026-07-17 18:12:48'),
(47,'COA-2017-004','Rice Thresher',9,1,'2017-09-26',41924.21,16,'Norma Gonzales',NULL,'Information and Communications Technology Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-29 09:00:00','2026-07-17 18:12:48'),
(48,'COA-2025-003','Rice Thresher',9,1,'2025-07-19',108523.70,3,'Elena Domingo',1,'Sangguniang Bayan Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-19 09:00:00','2026-07-17 18:12:48'),
(49,'COA-2018-003','Rice Thresher',9,1,'2018-12-04',45628.07,11,'Imelda Fernandez',1,'Municipal Planning and Development Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-06 09:00:00','2026-07-17 18:12:48'),
(50,'COA-2019-001','Service Vehicle (Sedan)',5,1,'2019-11-30',1988722.92,5,'Rosa Pascual',1,'Budget Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-03 09:00:00','2026-07-20 14:59:08'),
(51,'COA-2025-004','Service Pick-up Truck',5,1,'2025-11-05',912815.36,4,NULL,1,'Human Resource Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-07 09:00:00','2026-07-17 18:12:48'),
(52,'COA-2018-004','Hand Tractor',9,1,'2018-10-25',115451.20,16,'Maria Dela Cruz',1,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-26 09:00:00','2026-07-17 18:12:48'),
(53,'COA-2016-001','Water Dispenser (Hot & Cold)',1,1,'2016-11-04',31143.49,4,'Eduardo Gonzales',NULL,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2016-11-05 09:00:00','2026-07-17 18:12:48'),
(54,'COA-2023-004','Paper Shredder (Heavy Duty)',4,1,'2023-06-24',24928.08,8,'Leonora Aguilar',NULL,'Assessor\'s Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-24 09:00:00','2026-07-20 14:59:08'),
(55,'COA-2018-005','CCTV DVR/NVR Unit',7,1,'2018-01-04',41790.71,1,'Teresa Del Rosario',NULL,'Office of the Mayor - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-04 09:00:00','2026-07-20 14:59:08'),
(56,'COA-2019-002','Stretcher (Foldable)',8,1,'2019-06-04',27916.44,12,'Manuel Castillo',1,'Municipal Health Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-04 09:00:00','2026-07-20 14:59:08'),
(57,'COA-2016-002','Hand Tractor',9,1,'2016-04-23',35017.22,11,NULL,NULL,'Municipal Planning and Development Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-04-25 09:00:00','2026-07-17 18:12:48'),
(58,'COA-2017-005','PABX Telephone System',7,1,'2017-04-18',40728.95,17,'Maria Marquez',NULL,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-04-20 09:00:00','2026-07-20 14:59:08'),
(59,'COA-2020-002','Paper Shredder (Heavy Duty)',4,1,'2020-11-01',61830.22,12,NULL,1,'Municipal Health Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-03 09:00:00','2026-07-20 14:59:08'),
(60,'COA-2022-004','Base Radio Station',7,1,'2022-03-20',10653.20,10,'Manuel Del Rosario',1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-21 09:00:00','2026-07-17 18:12:48'),
(61,'COA-2021-001','Inflatable Rescue Boat',10,1,'2021-03-19',43120.86,11,'Josefa Ocampo',1,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-19 09:00:00','2026-07-17 18:12:48'),
(62,'COA-2018-006','Calculator (Desktop Printing)',4,1,'2018-07-09',12135.95,10,'Josefa Cruz',1,'Municipal Engineering Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-12 09:00:00','2026-07-20 14:59:08'),
(63,'COA-2022-005','Nebulizer Machine',8,1,'2022-04-08',114079.69,17,NULL,1,'Disaster Risk Reduction and Management Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-04-11 09:00:00','2026-07-20 14:59:08'),
(64,'COA-2018-007','Stretcher (Foldable)',8,1,'2018-11-27',101023.75,15,'Ernesto Rivera',1,'General Services Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-27 09:00:00','2026-07-20 14:59:08'),
(65,'COA-2017-006','Rice Thresher',9,1,'2017-07-20',71105.73,3,'Carlos Santos',1,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-20 09:00:00','2026-07-17 18:12:48'),
(66,'COA-2025-005','Emergency Light Tower',10,1,'2025-08-10',55539.20,1,'Carmen Villanueva',1,'Office of the Mayor - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-11 09:00:00','2026-07-20 14:59:08'),
(67,'COA-2018-008','Binding Machine',4,1,'2018-06-17',30021.83,16,'Antonio Del Rosario',NULL,'Information and Communications Technology Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-20 09:00:00','2026-07-20 14:59:08'),
(68,'COA-2023-005','Vacuum Cleaner',1,1,'2023-03-17',9624.22,3,'Maria Ramos',1,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-19 09:00:00','2026-07-17 18:12:48'),
(69,'COA-2025-006','Handheld Two-Way Radio',7,1,'2025-05-12',22488.04,9,'Maria Aquino',NULL,'Civil Registrar\'s Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-12 09:00:00','2026-07-20 14:59:08'),
(70,'COA-2018-009','Water Dispenser (Hot & Cold)',1,1,'2018-09-04',27361.96,5,'Carlos Pascual',1,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-07 09:00:00','2026-07-20 12:47:01'),
(71,'COA-2022-006','Service Vehicle (Sedan)',5,1,'2022-06-28',2075552.54,4,'Gloria Domingo',1,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-01 09:00:00','2026-07-17 18:12:48'),
(72,'COA-2024-003','Motorcycle (Service Unit)',5,1,'2024-12-05',1819611.86,4,'Teresa Del Rosario',1,'Human Resource Management Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-12-07 09:00:00','2026-07-17 18:12:48'),
(73,'COA-2020-003','Nebulizer Machine',8,1,'2020-11-10',76816.84,4,'Danilo Garcia',NULL,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-11 09:00:00','2026-07-17 18:12:48'),
(74,'COA-2025-007','Wheelchair',8,1,'2025-04-05',39693.09,14,'Gloria Santos',1,'Municipal Agriculture Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2025-04-05 09:00:00','2026-07-17 18:12:48'),
(75,'COA-2018-010','Bookshelf (Wooden, 5-Tier)',3,1,'2018-05-18',10321.08,16,NULL,1,'Information and Communications Technology Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-20 09:00:00','2026-07-17 18:12:48'),
(76,'COA-2023-006','Bulletin Board (Cork, Framed)',4,1,'2023-03-30',30786.82,16,'Luz Flores',1,'Information and Communications Technology Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-01 09:00:00','2026-07-17 18:12:48'),
(77,'COA-2019-003','Farm Tool Kit',9,2,'2019-12-12',51316.75,11,'Ana Ocampo',2,'Municipal Planning and Development Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-13 09:00:00','2026-07-17 18:12:48'),
(78,'COA-2022-007','Multi-Purpose Van',5,1,'2022-09-10',2165893.60,17,'Luz Flores',NULL,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-13 09:00:00','2026-07-17 18:12:48'),
(79,'COA-2017-007','Executive Office Desk',3,5,'2017-02-24',8820.29,16,'Antonio Mendoza',5,'Information and Communications Technology Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-24 09:00:00','2026-07-20 14:59:08'),
(80,'COA-2017-008','Microwave Oven',1,1,'2017-09-03',6972.00,5,'Cecilia Aguilar',NULL,'Budget Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-03 09:00:00','2026-07-20 12:47:01'),
(81,'COA-2019-004','Chainsaw (Rescue Type)',10,1,'2019-06-04',59755.54,14,'Norma Bautista',1,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-04 09:00:00','2026-07-20 14:59:08'),
(82,'COA-2023-007','CCTV Camera (Outdoor)',7,1,'2023-09-24',22471.28,15,'Luz Marquez',NULL,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-27 09:00:00','2026-07-17 18:12:48'),
(83,'COA-2017-009','Calculator (Desktop Printing)',4,1,'2017-04-15',43153.35,14,NULL,NULL,'Municipal Agriculture Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-04-15 09:00:00','2026-07-17 18:12:48'),
(84,'COA-2020-004','Fire Extinguisher (10lbs)',10,1,'2020-12-03',45588.91,10,'Manuel Ramos',NULL,'Municipal Engineering Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-12-03 09:00:00','2026-07-17 18:12:48'),
(85,'COA-2018-011','Electric Fan (Stand Type)',1,1,'2018-07-26',54977.55,3,'Ramon Navarro',1,'Sangguniang Bayan Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-26 09:00:00','2026-07-17 18:12:48'),
(86,'COA-2017-010','PABX Telephone System',7,1,'2017-01-08',17288.34,16,'Imelda Bautista',NULL,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-10 09:00:00','2026-07-17 18:12:48'),
(87,'COA-2019-005','Wheelchair',8,1,'2019-07-12',39807.94,3,NULL,1,'Sangguniang Bayan Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2019-07-13 09:00:00','2026-07-20 14:59:08'),
(88,'COA-2023-008','Inflatable Rescue Boat',10,1,'2023-01-05',72679.12,16,'Cecilia Garcia',1,'Information and Communications Technology Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-08 09:00:00','2026-07-20 14:59:08'),
(89,'COA-2022-008','Executive Office Desk',3,5,'2022-03-06',12134.15,10,'Alfredo Bautista',5,'Municipal Engineering Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-06 09:00:00','2026-07-17 18:12:48'),
(90,'COA-2021-002','Base Radio Station',7,1,'2021-04-18',21913.43,16,'Carlos Cruz',NULL,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-21 09:00:00','2026-07-20 14:59:08'),
(91,'COA-2025-008','Hand Tractor',9,1,'2025-03-14',131648.00,9,'Eduardo Del Rosario',NULL,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-16 09:00:00','2026-07-17 18:12:48'),
(92,'COA-2023-009','Road Roller',6,1,'2023-10-27',1979623.28,7,'Ernesto Aguilar',1,'Treasury Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-28 09:00:00','2026-07-20 14:59:08'),
(93,'COA-2016-003','Swivel Office Chair',3,5,'2016-05-31',27071.48,16,'Ana Pascual',5,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-02 09:00:00','2026-07-17 18:12:48'),
(94,'COA-2019-006','Autoclave Sterilizer',8,1,'2019-10-18',78505.64,9,NULL,NULL,'Civil Registrar\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2019-10-20 09:00:00','2026-07-17 18:12:48'),
(95,'COA-2018-012','Paper Shredder (Heavy Duty)',4,1,'2018-07-20',29906.23,10,'Rodrigo Marquez',1,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2018-07-21 09:00:00','2026-07-20 14:59:08'),
(96,'COA-2017-011','Road Roller',6,1,'2017-08-19',1863824.01,14,'Divina Mendoza',1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-21 09:00:00','2026-07-17 18:12:48'),
(97,'COA-2023-010','Binding Machine',4,1,'2023-02-25',31493.37,15,'Romeo Pascual',1,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-28 09:00:00','2026-07-17 18:12:48'),
(98,'COA-2021-003','Megaphone (Bullhorn)',7,1,'2021-02-14',15340.17,9,NULL,NULL,'Civil Registrar\'s Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-15 09:00:00','2026-07-20 14:59:08'),
(99,'COA-2016-004','CCTV Camera (Outdoor)',7,1,'2016-02-03',39265.36,9,'Maria Cruz',NULL,'Civil Registrar\'s Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-04 09:00:00','2026-07-20 14:59:08'),
(100,'COA-2023-011','Typewriter (Manual)',4,1,'2023-08-08',41951.38,9,NULL,1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-08 09:00:00','2026-07-17 18:12:48'),
(101,'COA-2018-013','Base Radio Station',7,1,'2018-04-02',35926.79,6,NULL,NULL,'Accounting Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-02 09:00:00','2026-07-20 14:59:08'),
(102,'COA-2025-009','Service Vehicle (Sedan)',5,1,'2025-01-07',1269579.93,11,'Ernesto Flores',1,'Municipal Planning and Development Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-10 09:00:00','2026-07-20 14:59:08'),
(103,'COA-2023-012','Wheelchair',8,1,'2023-07-18',70770.37,12,'Carmen Bautista',1,'Municipal Health Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-18 09:00:00','2026-07-20 14:59:08'),
(104,'COA-2023-013','Autoclave Sterilizer',8,1,'2023-04-13',15326.10,10,'Maria Villanueva',1,'Municipal Engineering Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-13 09:00:00','2026-07-20 14:59:08'),
(105,'COA-2022-009','Farm Tool Kit',9,1,'2022-08-02',159775.53,14,'Alfredo Salazar',1,'Municipal Agriculture Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-04 09:00:00','2026-07-20 14:59:08'),
(106,'COA-2023-014','Bulldozer',6,1,'2023-09-09',1901727.71,4,NULL,NULL,'Human Resource Management Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-09-10 09:00:00','2026-07-17 18:12:48'),
(107,'COA-2023-015','Stretcher (Foldable)',8,1,'2023-06-07',77541.98,3,'Juan Reyes',1,'Sangguniang Bayan Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-09 09:00:00','2026-07-17 18:12:48'),
(108,'COA-2024-004','Typewriter (Manual)',4,1,'2024-09-06',51895.91,11,'Ramon Garcia',1,'Municipal Planning and Development Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-07 09:00:00','2026-07-20 14:59:08'),
(109,'COA-2016-005','Typewriter (Manual)',4,1,'2016-03-05',19452.79,11,'Teresa Rivera',1,'Municipal Planning and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-05 09:00:00','2026-07-17 18:12:48'),
(110,'COA-2024-005','Emergency Light Tower',10,1,'2024-02-26',86513.91,2,'Luz Pascual',1,'Office of the Vice Mayor - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-02-28 09:00:00','2026-07-17 18:12:48'),
(111,'COA-2016-006','Weighing Scale (Digital)',8,1,'2016-10-28',39670.25,15,'Pedro Ramos',1,'General Services Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-29 09:00:00','2026-07-17 18:12:48'),
(112,'COA-2017-012','Emergency Light Tower',10,1,'2017-02-10',67265.49,14,NULL,1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-11 09:00:00','2026-07-17 18:12:48'),
(113,'COA-2019-007','PABX Telephone System',7,1,'2019-07-04',15782.25,4,'Pedro Del Rosario',1,'Human Resource Management Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-07-06 09:00:00','2026-07-20 14:59:08'),
(114,'COA-2022-010','Backhoe Loader',6,1,'2022-03-28',2021425.49,5,'Antonio Del Rosario',NULL,'Budget Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2022-03-31 09:00:00','2026-07-20 12:47:01'),
(115,'COA-2019-008','Fire Extinguisher (10lbs)',10,1,'2019-12-11',55746.42,10,'Imelda Salazar',1,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-12 09:00:00','2026-07-17 18:12:48'),
(116,'COA-2022-011','CCTV DVR/NVR Unit',7,1,'2022-10-30',37752.08,1,'Rosa Ramos',1,'Office of the Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2022-11-01 09:00:00','2026-07-17 18:12:48'),
(117,'COA-2018-014','LCD/LED Monitor 24\"',2,1,'2018-05-31',39746.93,17,'Carmen Villanueva',NULL,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2018-05-31 09:00:00','2026-07-20 14:59:08'),
(118,'COA-2023-016','Ambulance Unit',5,1,'2023-06-04',1299907.98,15,'Ramon Torres',1,'General Services Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-06 09:00:00','2026-07-20 14:59:08'),
(119,'COA-2018-015','Ambulance Unit',5,1,'2018-06-22',2172779.90,2,'Carlos Villanueva',1,'Office of the Vice Mayor - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-25 09:00:00','2026-07-20 14:59:08'),
(120,'COA-2021-004','Visitor\'s Chair (Stackable)',3,5,'2021-12-21',16173.79,13,'Carmen Santos',NULL,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-21 09:00:00','2026-07-20 14:59:08'),
(121,'COA-2023-017','Metal Detector (Handheld)',10,1,'2023-12-16',40845.54,13,'Juan Castillo',1,'Municipal Social Welfare and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-18 09:00:00','2026-07-20 14:59:08'),
(122,'COA-2022-012','Fax Machine',4,1,'2022-08-09',35485.68,14,'Luz Ocampo',1,'Municipal Agriculture Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-12 09:00:00','2026-07-20 14:59:08'),
(123,'COA-2024-006','Concrete Mixer',6,1,'2024-02-27',2189512.48,12,'Ana Garcia',1,'Municipal Health Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-29 09:00:00','2026-07-17 18:12:48'),
(124,'COA-2024-007','Thermal Scanner',8,1,'2024-06-17',82214.32,15,NULL,1,'General Services Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-19 09:00:00','2026-07-20 14:59:08'),
(125,'COA-2019-009','Motorcycle (Service Unit)',5,1,'2019-12-12',579833.65,2,'Maria Reyes',1,'Office of the Vice Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-14 09:00:00','2026-07-20 14:59:08'),
(126,'COA-2021-005','Stretcher (Foldable)',8,1,'2021-01-16',39600.92,2,'Pedro Reyes',1,'Office of the Vice Mayor - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-18 09:00:00','2026-07-17 18:12:48'),
(127,'COA-2023-018','Water Cooler/Dispenser',1,1,'2023-12-08',54526.77,8,'Corazon Mendoza',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-08 09:00:00','2026-07-17 18:12:48'),
(128,'COA-2019-010','Backhoe Loader',6,1,'2019-09-12',1940195.16,3,'Ramon Ocampo',1,'Sangguniang Bayan Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-15 09:00:00','2026-07-17 18:12:48'),
(129,'COA-2022-013','CCTV DVR/NVR Unit',7,1,'2022-09-03',42365.09,5,'Manuel Fernandez',1,'Budget Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-04 09:00:00','2026-07-20 14:59:08'),
(130,'COA-2020-005','Bulldozer',6,1,'2020-01-25',863749.33,1,'Ernesto Salazar',1,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-26 09:00:00','2026-07-20 14:59:08'),
(131,'COA-2023-019','Water Pump (Irrigation)',9,5,'2023-06-04',26630.16,2,'Rosa Mendoza',5,'Office of the Vice Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-06 09:00:00','2026-07-17 18:12:48'),
(132,'COA-2024-008','Thermal Scanner',8,1,'2024-06-08',29229.35,10,'Divina Salazar',1,'Municipal Engineering Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-08 09:00:00','2026-07-20 14:59:08'),
(133,'COA-2017-013','Rice Thresher',9,5,'2017-10-25',27927.34,14,'Rodrigo Salazar',5,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-27 09:00:00','2026-07-20 14:59:08'),
(134,'COA-2018-016','Desktop Computer Set (Core i5)',2,1,'2018-07-08',31857.42,12,'Danilo Fernandez',1,'Municipal Health Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-10 09:00:00','2026-07-17 18:12:48'),
(135,'COA-2022-014','Digital Blood Pressure Monitor',8,1,'2022-11-25',108844.11,15,'Carlos Garcia',1,'General Services Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-25 09:00:00','2026-07-17 18:12:48'),
(136,'COA-2023-020','Bulletin Board (Cork, Framed)',4,1,'2023-03-02',6894.04,14,'Josefa Cruz',1,'Municipal Agriculture Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-03-02 09:00:00','2026-07-17 18:12:48'),
(137,'COA-2022-015','IP Desk Phone',7,1,'2022-11-23',12723.98,1,'Imelda Del Rosario',NULL,'Office of the Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-24 09:00:00','2026-07-20 14:59:08'),
(138,'COA-2025-010','Water Cooler/Dispenser',1,1,'2025-10-17',4785.56,13,'Carmen Ramos',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-19 09:00:00','2026-07-17 18:12:48'),
(139,'COA-2016-007','Bulldozer',6,1,'2016-06-30',1906139.17,5,'Rosa Del Rosario',NULL,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-01 09:00:00','2026-07-20 12:47:01'),
(140,'COA-2018-017','Electric Fan (Stand Type)',1,1,'2018-04-05',44033.23,10,NULL,1,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-05 09:00:00','2026-07-20 14:59:08'),
(141,'COA-2020-006','Photocopier Machine (Multi-function)',4,1,'2020-01-02',56679.49,10,'Ana Aquino',1,'Municipal Engineering Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-02 09:00:00','2026-07-20 14:59:08'),
(142,'COA-2024-009','Wheelchair',8,1,'2024-12-09',96436.05,12,'Jose Aguilar',1,'Municipal Health Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-12-10 09:00:00','2026-07-17 18:12:48'),
(143,'COA-2017-014','Thermal Scanner',8,1,'2017-11-13',43158.32,14,'Leonora Aquino',1,'Municipal Agriculture Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-13 09:00:00','2026-07-20 14:59:08'),
(144,'COA-2024-010','Generator Set (25 kVA)',6,1,'2024-12-25',2286320.23,17,NULL,1,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-12-28 09:00:00','2026-07-17 18:12:48'),
(145,'COA-2022-016','Backhoe Loader',6,1,'2022-05-12',2074520.26,13,'Carmen Aquino',1,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-15 09:00:00','2026-07-17 18:12:48'),
(146,'COA-2024-011','Laser Printer (Monochrome)',2,1,'2024-04-01',45925.43,1,'Cecilia Bautista',1,'Office of the Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-04 09:00:00','2026-07-17 18:12:48'),
(147,'COA-2017-015','Paper Shredder (Heavy Duty)',4,1,'2017-07-09',31026.65,4,NULL,1,'Human Resource Management Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-12 09:00:00','2026-07-17 18:12:48'),
(148,'COA-2025-011','Water Pump (Irrigation)',9,1,'2025-12-29',129134.31,10,NULL,1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-29 09:00:00','2026-07-20 14:59:08'),
(149,'COA-2022-017','Electric Kettle',1,1,'2022-03-19',27038.81,12,NULL,NULL,'Municipal Health Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-21 09:00:00','2026-07-17 18:12:48'),
(150,'COA-2017-016','IP Desk Phone',7,1,'2017-05-28',29799.39,3,'Imelda Rivera',NULL,'Sangguniang Bayan Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-29 09:00:00','2026-07-20 14:59:08'),
(151,'COA-2025-012','Hand Tractor',9,5,'2025-04-28',30507.23,2,'Antonio Marquez',5,'Office of the Vice Mayor - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-28 09:00:00','2026-07-20 14:59:08'),
(152,'COA-2017-017','Farm Tool Kit',9,1,'2017-05-27',111946.59,9,'Rodrigo Mendoza',1,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-29 09:00:00','2026-07-17 18:12:48'),
(153,'COA-2025-013','Emergency Light Tower',10,1,'2025-04-03',4638.73,2,'Rodrigo Navarro',1,'Office of the Vice Mayor - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-06 09:00:00','2026-07-20 14:59:08'),
(154,'COA-2021-006','Service Pick-up Truck',5,1,'2021-06-01',1858204.27,10,'Luz Pascual',1,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-01 09:00:00','2026-07-17 18:12:48'),
(155,'COA-2020-007','Road Roller',6,1,'2020-06-21',2517895.24,12,'Ana Castillo',1,'Municipal Health Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-06-23 09:00:00','2026-07-17 18:12:48'),
(156,'COA-2018-018','Emergency Light Tower',10,1,'2018-10-13',85914.91,14,'Gloria Navarro',NULL,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-14 09:00:00','2026-07-20 14:59:08'),
(157,'COA-2021-007','External Hard Drive 2TB',2,1,'2021-09-01',82401.56,13,'Carmen Reyes',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2021-09-03 09:00:00','2026-07-20 14:59:08'),
(158,'COA-2025-014','IP Desk Phone',7,1,'2025-11-23',33419.09,5,'Carmen Reyes',1,'Budget Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-11-24 09:00:00','2026-07-20 12:47:01'),
(159,'COA-2021-008','Megaphone (Bullhorn)',7,1,'2021-01-18',25868.93,17,'Corazon Del Rosario',NULL,'Disaster Risk Reduction and Management Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-18 09:00:00','2026-07-17 18:12:48'),
(160,'COA-2018-019','Grass Cutter (Riding Type)',6,1,'2018-03-26',1800999.17,5,'Maria Reyes',NULL,'Budget Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-26 09:00:00','2026-07-20 14:59:08'),
(161,'COA-2017-018','Inflatable Rescue Boat',10,1,'2017-10-27',94127.26,11,'Luz Navarro',1,'Municipal Planning and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2017-10-28 09:00:00','2026-07-17 18:12:48'),
(162,'COA-2022-018','Wireless Router',2,1,'2022-07-18',69146.88,14,'Danilo Fernandez',1,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-20 09:00:00','2026-07-17 18:12:48'),
(163,'COA-2017-019','Vacuum Cleaner',1,1,'2017-11-29',10258.22,16,'Maria Navarro',1,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-01 09:00:00','2026-07-17 18:12:48'),
(164,'COA-2025-015','Emergency Light Tower',10,1,'2025-10-15',70432.87,16,'Pedro Rivera',NULL,'Information and Communications Technology Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-18 09:00:00','2026-07-20 14:59:08'),
(165,'COA-2022-019','Water Pump (Irrigation)',9,1,'2022-02-15',111178.52,11,'Elena Ramos',NULL,'Municipal Planning and Development Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-16 09:00:00','2026-07-20 14:59:08'),
(166,'COA-2021-009','Nebulizer Machine',8,1,'2021-05-19',67917.78,11,NULL,1,'Municipal Planning and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-19 09:00:00','2026-07-17 18:12:48'),
(167,'COA-2016-008','Conference Table (8-Seater)',3,1,'2016-06-21',10482.54,10,'Ramon Ocampo',1,'Municipal Engineering Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-22 09:00:00','2026-07-20 14:59:08'),
(168,'COA-2018-020','Fire Extinguisher (10lbs)',10,1,'2018-09-20',64294.56,8,'Rodrigo Flores',NULL,'Assessor\'s Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-09-23 09:00:00','2026-07-20 14:59:08'),
(169,'COA-2021-010','CCTV DVR/NVR Unit',7,1,'2021-05-09',10976.88,16,NULL,1,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-09 09:00:00','2026-07-17 18:12:48'),
(170,'COA-2020-008','Water Dispenser (Hot & Cold)',1,1,'2020-09-07',51530.94,6,'Alfredo Domingo',NULL,'Accounting Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2020-09-08 09:00:00','2026-07-20 14:59:08'),
(171,'COA-2021-011','Generator Set (25 kVA)',6,1,'2021-02-04',1898406.38,10,'Pedro Rivera',1,'Municipal Engineering Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-07 09:00:00','2026-07-20 14:59:08'),
(172,'COA-2024-012','Microwave Oven',1,1,'2024-11-12',32308.51,11,'Rosa Cruz',1,'Municipal Planning and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-15 09:00:00','2026-07-20 14:59:08'),
(173,'COA-2016-009','Bulldozer',6,1,'2016-01-28',1443187.01,8,'Ramon Castillo',1,'Assessor\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-29 09:00:00','2026-07-17 18:12:48'),
(174,'COA-2017-020','Autoclave Sterilizer',8,1,'2017-10-16',82799.72,10,NULL,1,'Municipal Engineering Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-16 09:00:00','2026-07-20 14:59:08'),
(175,'COA-2021-012','Nebulizer Machine',8,1,'2021-02-06',50777.71,5,'Josefa Gonzales',1,'Budget Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-07 09:00:00','2026-07-20 12:47:01'),
(176,'COA-2026-023','Grass Cutter (Riding Type)',6,1,'2026-04-15',669795.06,3,'Romeo Rivera',1,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-15 09:00:00','2026-07-17 18:12:48'),
(177,'COA-2017-021','Chainsaw (Rescue Type)',10,1,'2017-01-07',43429.89,16,'Pedro Rivera',NULL,'Information and Communications Technology Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-09 09:00:00','2026-07-17 18:12:48'),
(178,'COA-2022-020','Refrigerator (2-Door)',1,1,'2022-06-26',4877.71,7,'Jose Gonzales',1,'Treasury Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-29 09:00:00','2026-07-20 14:59:08'),
(179,'COA-2025-016','PABX Telephone System',7,1,'2025-12-29',21562.83,12,NULL,1,'Municipal Health Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-31 09:00:00','2026-07-17 18:12:48'),
(180,'COA-2021-013','Swivel Office Chair',3,1,'2021-12-06',23573.22,13,'Luz Pascual',1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-08 09:00:00','2026-07-17 18:12:48'),
(181,'COA-2025-017','LCD/LED Monitor 24\"',2,1,'2025-01-28',54964.01,2,NULL,1,'Office of the Vice Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-29 09:00:00','2026-07-17 18:12:48'),
(182,'COA-2020-009','Bulletin Board (Cork, Framed)',4,1,'2020-07-05',17529.04,2,'Leonora Reyes',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-05 09:00:00','2026-07-20 14:59:08'),
(183,'COA-2019-011','Road Roller',6,1,'2019-05-21',3159232.35,8,'Teresa Villanueva',NULL,'Assessor\'s Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-05-24 09:00:00','2026-07-20 14:59:08'),
(184,'COA-2016-010','IP Desk Phone',7,1,'2016-07-11',42517.42,16,'Divina Rivera',1,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-13 09:00:00','2026-07-17 18:12:48'),
(185,'COA-2025-018','Typewriter (Manual)',4,1,'2025-08-13',52958.12,10,NULL,1,'Municipal Engineering Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-16 09:00:00','2026-07-17 18:12:48'),
(186,'COA-2025-019','24-Port Network Switch',2,1,'2025-07-01',14212.19,15,'Carlos Reyes',1,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-01 09:00:00','2026-07-20 14:59:08'),
(187,'COA-2026-024','Backhoe Loader',6,1,'2026-03-12',953652.15,10,'Norma Bautista',1,'Municipal Engineering Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-13 09:00:00','2026-07-17 18:12:48'),
(188,'COA-2021-014','Motorcycle (Service Unit)',5,1,'2021-03-24',1585262.34,13,'Carmen Rivera',1,'Municipal Social Welfare and Development Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-26 09:00:00','2026-07-20 14:59:08'),
(189,'COA-2016-011','Grass Cutter (Riding Type)',6,1,'2016-07-06',2812641.80,14,'Juan Ramos',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-06 09:00:00','2026-07-17 18:12:48'),
(190,'COA-2022-021','Laminating Machine',4,1,'2022-03-05',18954.26,16,'Norma Fernandez',1,'Information and Communications Technology Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-07 09:00:00','2026-07-17 18:12:48'),
(191,'COA-2021-015','Hand Tractor',9,1,'2021-11-16',170325.70,2,'Ernesto Dela Cruz',1,'Office of the Vice Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-11-16 09:00:00','2026-07-20 14:59:08'),
(192,'COA-2023-021','Water Cooler/Dispenser',1,1,'2023-05-24',3325.92,16,'Teresa Dela Cruz',NULL,'Information and Communications Technology Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-26 09:00:00','2026-07-20 14:59:08'),
(193,'COA-2021-016','Laser Printer (Monochrome)',2,1,'2021-11-17',25795.57,4,'Ramon Aquino',1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-11-17 09:00:00','2026-07-20 14:59:08'),
(194,'COA-2023-022','Patrol Motorcycle',5,1,'2023-05-01',1587315.29,3,'Manuel Domingo',1,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-03 09:00:00','2026-07-20 14:59:08'),
(195,'COA-2026-025','Grass Cutter (Riding Type)',6,1,'2026-01-13',2969583.81,4,'Romeo Marquez',NULL,'Human Resource Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-13 09:00:00','2026-07-20 14:59:08'),
(196,'COA-2025-020','Electric Kettle',1,1,'2025-07-15',3322.05,6,'Pedro Marquez',NULL,'Accounting Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-15 09:00:00','2026-07-17 18:12:48'),
(197,'COA-2020-010','Farm Tool Kit',9,1,'2020-04-21',143022.91,11,'Jose Rivera',1,'Municipal Planning and Development Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-04-21 09:00:00','2026-07-17 18:12:48'),
(198,'COA-2024-013','Life Vest',10,1,'2024-09-03',4755.19,13,'Francisco Salazar',1,'Municipal Social Welfare and Development Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2024-09-04 09:00:00','2026-07-20 14:59:08'),
(199,'COA-2016-012','Binding Machine',4,1,'2016-12-02',12561.70,3,'Rodrigo Garcia',1,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-05 09:00:00','2026-07-20 14:59:08'),
(200,'COA-2018-021','Steel Locker Cabinet',3,2,'2018-02-06',16127.20,3,'Ana Dela Cruz',2,'Sangguniang Bayan Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-06 09:00:00','2026-07-17 18:12:48'),
(201,'COA-2024-014','CCTV Camera (Outdoor)',7,1,'2024-02-16',40971.32,3,NULL,1,'Sangguniang Bayan Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-19 09:00:00','2026-07-17 18:12:48'),
(202,'COA-2019-012','Steel Locker Cabinet',3,1,'2019-02-04',14177.40,14,'Ramon Flores',NULL,'Municipal Agriculture Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-04 09:00:00','2026-07-20 14:59:08'),
(203,'COA-2025-021','Emergency Light Tower',10,1,'2025-01-06',32647.38,13,'Alfredo Fernandez',1,'Municipal Social Welfare and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-06 09:00:00','2026-07-20 14:59:08'),
(204,'COA-2024-015','Generator Set (25 kVA)',6,1,'2024-03-29',2153772.02,10,NULL,NULL,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-29 09:00:00','2026-07-17 18:12:48'),
(205,'COA-2023-023','Seedling Tray Set',9,1,'2023-08-24',171705.31,6,'Danilo Torres',NULL,'Accounting Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-26 09:00:00','2026-07-20 14:59:08'),
(206,'COA-2018-022','Conference Table (8-Seater)',3,1,'2018-09-18',20368.34,10,'Jose Pascual',1,'Municipal Engineering Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-20 09:00:00','2026-07-17 18:12:48'),
(207,'COA-2017-022','Concrete Mixer',6,1,'2017-03-23',1057458.26,3,'Rosa Fernandez',1,'Sangguniang Bayan Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-03-25 09:00:00','2026-07-20 14:59:08'),
(208,'COA-2017-023','Backhoe Loader',6,1,'2017-03-09',631028.69,14,'Norma Rivera',NULL,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-09 09:00:00','2026-07-17 18:12:48'),
(209,'COA-2019-013','Hand Tractor',9,2,'2019-11-13',21952.96,5,'Jose Bautista',2,'Budget Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2019-11-14 09:00:00','2026-07-20 12:47:01'),
(210,'COA-2019-014','Backhoe Loader',6,1,'2019-05-14',2659029.92,3,'Leonora Castillo',1,'Sangguniang Bayan Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-15 09:00:00','2026-07-20 14:59:08'),
(211,'COA-2021-017','Rice Thresher',9,2,'2021-03-07',114652.70,14,'Imelda Aguilar',2,'Municipal Agriculture Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-03-09 09:00:00','2026-07-17 18:12:48'),
(212,'COA-2023-024','Base Radio Station',7,1,'2023-11-26',11245.84,1,'Divina Santos',1,'Office of the Mayor - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-26 09:00:00','2026-07-20 14:59:08'),
(213,'COA-2023-025','Nebulizer Machine',8,1,'2023-03-02',72241.04,17,'Eduardo Bautista',NULL,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-02 09:00:00','2026-07-17 18:12:48'),
(214,'COA-2023-026','Rescue Rope Kit',10,1,'2023-07-15',31126.27,3,'Ana Mendoza',1,'Sangguniang Bayan Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-17 09:00:00','2026-07-17 18:12:48'),
(215,'COA-2022-022','Rice Thresher',9,2,'2022-03-22',54479.34,6,'Alfredo Pascual',2,'Accounting Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-03-24 09:00:00','2026-07-17 18:12:48'),
(216,'COA-2023-027','PABX Telephone System',7,1,'2023-04-28',19888.21,17,'Danilo Pascual',1,'Disaster Risk Reduction and Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-29 09:00:00','2026-07-17 18:12:48'),
(217,'COA-2024-016','Ambulance Unit',5,1,'2024-10-02',1439888.31,6,'Josefa Gonzales',NULL,'Accounting Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-04 09:00:00','2026-07-20 14:59:08'),
(218,'COA-2020-011','Weighing Scale (Digital)',8,1,'2020-10-07',88714.66,7,'Elena Villanueva',NULL,'Treasury Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-09 09:00:00','2026-07-20 14:59:08'),
(219,'COA-2025-022','Laminating Machine',4,1,'2025-02-02',56385.02,7,'Teresa Mendoza',1,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-02-03 09:00:00','2026-07-17 18:12:48'),
(220,'COA-2023-028','Conference Table (8-Seater)',3,1,'2023-11-23',16549.31,11,NULL,NULL,'Municipal Planning and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-26 09:00:00','2026-07-20 14:59:08'),
(221,'COA-2023-029','Patrol Motorcycle',5,1,'2023-11-13',682209.00,5,'Antonio Flores',1,'Budget Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-14 09:00:00','2026-07-20 12:47:01'),
(222,'COA-2021-018','Wireless Router',2,1,'2021-10-12',61186.88,13,NULL,NULL,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-10-14 09:00:00','2026-07-20 14:59:08'),
(223,'COA-2025-023','Weighing Scale (Digital)',8,1,'2025-07-14',95787.83,12,'Teresa Torres',1,'Municipal Health Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-16 09:00:00','2026-07-20 14:59:08'),
(224,'COA-2016-013','Backhoe Loader',6,1,'2016-07-07',2134611.64,2,'Juan Bautista',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-10 09:00:00','2026-07-20 14:59:08'),
(225,'COA-2025-024','Multi-Purpose Van',5,1,'2025-10-21',613344.97,6,'Jose Aquino',NULL,'Accounting Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-10-21 09:00:00','2026-07-17 18:12:48'),
(226,'COA-2023-030','Handheld Two-Way Radio',7,1,'2023-11-22',2546.17,3,'Pedro Navarro',1,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-24 09:00:00','2026-07-20 14:59:08'),
(227,'COA-2016-014','Visitor\'s Chair (Stackable)',3,2,'2016-10-17',3594.07,16,'Ana Castillo',2,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-19 09:00:00','2026-07-17 18:12:48'),
(228,'COA-2021-019','Executive Office Desk',3,5,'2021-12-12',18620.54,3,'Norma Torres',NULL,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-12 09:00:00','2026-07-17 18:12:48'),
(229,'COA-2019-015','LCD/LED Monitor 24\"',2,1,'2019-12-10',31531.29,13,'Ramon Fernandez',NULL,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2019-12-11 09:00:00','2026-07-17 18:12:48'),
(230,'COA-2022-023','Calculator (Desktop Printing)',4,1,'2022-10-21',49366.31,17,'Maria Flores',NULL,'Disaster Risk Reduction and Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-24 09:00:00','2026-07-17 18:12:48'),
(231,'COA-2025-025','Steel Locker Cabinet',3,1,'2025-08-26',15842.35,13,'Josefa Santos',NULL,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-26 09:00:00','2026-07-17 18:12:48'),
(232,'COA-2024-017','Ambulance Unit',5,1,'2024-08-08',1191256.66,17,'Rodrigo Gonzales',1,'Disaster Risk Reduction and Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-08 09:00:00','2026-07-17 18:12:48'),
(233,'COA-2020-012','Seedling Tray Set',9,1,'2020-05-19',58244.92,11,'Leonora Flores',1,'Municipal Planning and Development Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-19 09:00:00','2026-07-20 14:59:08'),
(234,'COA-2016-015','Swivel Office Chair',3,1,'2016-02-21',5590.71,4,NULL,NULL,'Human Resource Management Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-22 09:00:00','2026-07-20 14:59:08'),
(235,'COA-2019-016','LCD/LED Monitor 24\"',2,1,'2019-10-04',28214.49,1,'Danilo Navarro',1,'Office of the Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-05 09:00:00','2026-07-20 14:59:08'),
(236,'COA-2018-023','UPS (Uninterruptible Power Supply)',2,1,'2018-07-24',7200.34,4,NULL,NULL,'Human Resource Management Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-24 09:00:00','2026-07-17 18:12:48'),
(237,'COA-2018-024','Water Pump (Irrigation)',9,1,'2018-07-08',76969.29,14,'Ramon Santos',1,'Municipal Agriculture Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-10 09:00:00','2026-07-20 14:59:08'),
(238,'COA-2016-016','Water Cooler/Dispenser',1,1,'2016-10-09',47966.69,13,'Luz Castillo',1,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-10 09:00:00','2026-07-17 18:12:48'),
(239,'COA-2022-024','Thermal Scanner',8,1,'2022-08-20',119737.77,12,'Norma Gonzales',1,'Municipal Health Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-22 09:00:00','2026-07-20 14:59:08'),
(240,'COA-2016-017','Vacuum Cleaner',1,1,'2016-01-06',47072.81,11,'Ana Torres',1,'Municipal Planning and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-06 09:00:00','2026-07-20 14:59:08'),
(241,'COA-2026-026','Vacuum Cleaner',1,1,'2026-01-23',39294.46,8,'Norma Santos',1,'Assessor\'s Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-26 09:00:00','2026-07-20 14:59:08'),
(242,'COA-2018-025','Laminating Machine',4,1,'2018-12-05',60414.60,10,'Alfredo Ocampo',NULL,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-08 09:00:00','2026-07-20 14:59:08'),
(243,'COA-2017-024','Partition Divider Panel',3,2,'2017-11-04',9616.09,4,'Carmen Torres',2,'Human Resource Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-04 09:00:00','2026-07-20 14:59:08'),
(244,'COA-2018-026','Emergency Light Tower',10,1,'2018-05-30',81661.31,2,'Danilo Flores',1,'Office of the Vice Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-30 09:00:00','2026-07-17 18:12:48'),
(245,'COA-2017-025','Thermal Scanner',8,1,'2017-01-22',13576.02,8,'Ana Dela Cruz',1,'Assessor\'s Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-22 09:00:00','2026-07-20 14:59:08'),
(246,'COA-2026-027','Laptop Computer (Business Series)',2,1,'2026-04-15',8700.41,9,'Romeo Fernandez',1,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-17 09:00:00','2026-07-20 14:59:08'),
(247,'COA-2022-025','Vacuum Cleaner',1,1,'2022-06-08',45638.48,6,'Juan Domingo',NULL,'Accounting Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2022-06-09 09:00:00','2026-07-17 18:12:48'),
(248,'COA-2020-013','Motorcycle (Service Unit)',5,1,'2020-08-14',1288304.13,16,'Manuel Garcia',NULL,'Information and Communications Technology Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-15 09:00:00','2026-07-20 14:59:08'),
(249,'COA-2021-020','CCTV Camera (Outdoor)',7,1,'2021-05-18',35710.99,12,'Eduardo Rivera',NULL,'Municipal Health Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-20 09:00:00','2026-07-17 18:12:48'),
(250,'COA-2021-021','Electric Kettle',1,1,'2021-12-08',42759.21,16,NULL,NULL,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-08 09:00:00','2026-07-17 18:12:48'),
(251,'COA-2019-017','Typewriter (Manual)',4,1,'2019-12-24',13918.22,13,'Divina Ocampo',1,'Municipal Social Welfare and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-27 09:00:00','2026-07-17 18:12:48'),
(252,'COA-2022-026','Binding Machine',4,1,'2022-01-29',13884.52,16,'Maria Flores',1,'Information and Communications Technology Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-31 09:00:00','2026-07-20 14:59:08'),
(253,'COA-2016-018','Executive Office Desk',3,1,'2016-08-31',16921.13,11,NULL,NULL,'Municipal Planning and Development Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-01 09:00:00','2026-07-17 18:12:48'),
(254,'COA-2019-018','24-Port Network Switch',2,1,'2019-05-21',17643.23,11,'Teresa Fernandez',NULL,'Municipal Planning and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-24 09:00:00','2026-07-20 14:59:08'),
(255,'COA-2020-014','Binding Machine',4,1,'2020-03-29',48507.69,6,'Rosa Ocampo',NULL,'Accounting Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2020-03-29 09:00:00','2026-07-20 14:59:08'),
(256,'COA-2023-031','Chainsaw (Rescue Type)',10,1,'2023-03-04',11682.25,8,'Antonio Ocampo',1,'Assessor\'s Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-05 09:00:00','2026-07-20 14:59:08'),
(257,'COA-2016-019','Bulldozer',6,1,'2016-02-16',947600.21,15,'Carmen Ramos',1,'General Services Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-16 09:00:00','2026-07-17 18:12:48'),
(258,'COA-2022-027','PABX Telephone System',7,1,'2022-02-14',6810.71,12,'Leonora Navarro',1,'Municipal Health Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-17 09:00:00','2026-07-20 14:59:08'),
(259,'COA-2019-019','Laser Printer (Monochrome)',2,1,'2019-11-01',76258.64,3,'Jose Gonzales',1,'Sangguniang Bayan Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-04 09:00:00','2026-07-20 14:59:08'),
(260,'COA-2017-026','Fire Extinguisher (10lbs)',10,1,'2017-10-05',11416.98,14,'Carlos Aguilar',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2017-10-07 09:00:00','2026-07-17 18:12:48'),
(261,'COA-2020-015','Executive Office Desk',3,2,'2020-01-17',3548.44,2,'Rodrigo Cruz',2,'Office of the Vice Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-17 09:00:00','2026-07-17 18:12:48'),
(262,'COA-2021-022','Ambulance Unit',5,1,'2021-04-12',2016035.60,13,'Rodrigo Gonzales',1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-12 09:00:00','2026-07-20 14:59:08'),
(263,'COA-2022-028','Photocopier Machine (Multi-function)',4,1,'2022-04-30',12370.10,9,'Ana Santos',1,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-04-30 09:00:00','2026-07-17 18:12:48'),
(264,'COA-2022-029','Farm Tool Kit',9,2,'2022-01-02',104584.07,14,'Luz Santos',NULL,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-02 09:00:00','2026-07-17 18:12:48'),
(265,'COA-2017-027','Emergency Light Tower',10,1,'2017-05-07',43760.70,5,NULL,NULL,'Budget Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-07 09:00:00','2026-07-20 14:59:08'),
(266,'COA-2019-020','Steel Filing Cabinet (4-Drawer)',3,1,'2019-08-02',11601.06,9,'Antonio Ramos',1,'Civil Registrar\'s Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-03 09:00:00','2026-07-20 14:59:08'),
(267,'COA-2017-028','CCTV Camera (Outdoor)',7,1,'2017-08-30',27487.20,5,'Ana Bautista',NULL,'Budget Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-31 09:00:00','2026-07-20 14:59:08'),
(268,'COA-2016-020','Oxygen Tank with Regulator',8,1,'2016-06-02',34136.58,16,'Corazon Del Rosario',1,'Information and Communications Technology Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-06-03 09:00:00','2026-07-20 14:59:08'),
(269,'COA-2026-028','Nebulizer Machine',8,1,'2026-01-22',3897.60,9,'Luz Villanueva',1,'Civil Registrar\'s Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-22 09:00:00','2026-07-20 14:59:08'),
(270,'COA-2019-021','Autoclave Sterilizer',8,1,'2019-01-08',73190.03,11,'Francisco Torres',1,'Municipal Planning and Development Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-08 09:00:00','2026-07-20 14:59:08'),
(271,'COA-2020-016','Service Pick-up Truck',5,1,'2020-07-10',1815903.75,17,'Eduardo Dela Cruz',1,'Disaster Risk Reduction and Management Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2020-07-13 09:00:00','2026-07-20 14:59:08'),
(272,'COA-2020-017','Bulletin Board (Cork, Framed)',4,1,'2020-02-17',34317.84,9,'Ana Del Rosario',1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-20 09:00:00','2026-07-17 18:12:48'),
(273,'COA-2025-026','Bulldozer',6,1,'2025-05-24',2484539.23,6,'Luz Dela Cruz',1,'Accounting Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-05-27 09:00:00','2026-07-20 14:59:08'),
(274,'COA-2023-032','Calculator (Desktop Printing)',4,1,'2023-08-07',19683.18,8,'Juan Del Rosario',1,'Assessor\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-09 09:00:00','2026-07-17 18:12:48'),
(275,'COA-2020-018','Ambulance Unit',5,1,'2020-10-01',1940275.80,9,'Carlos Pascual',1,'Civil Registrar\'s Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-03 09:00:00','2026-07-20 14:59:08'),
(276,'COA-2019-022','Generator Set (25 kVA)',6,1,'2019-05-07',658097.91,10,'Ramon Fernandez',1,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-10 09:00:00','2026-07-17 18:12:48'),
(277,'COA-2025-027','Fax Machine',4,1,'2025-01-12',43952.88,2,'Norma Dela Cruz',1,'Office of the Vice Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-15 09:00:00','2026-07-17 18:12:48'),
(278,'COA-2019-023','Metal Detector (Handheld)',10,1,'2019-11-06',68343.34,7,'Rodrigo Salazar',1,'Treasury Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-07 09:00:00','2026-07-20 14:59:08'),
(279,'COA-2023-033','Multi-Purpose Van',5,1,'2023-08-16',1595260.63,6,'Elena Ocampo',1,'Accounting Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-17 09:00:00','2026-07-20 14:59:08'),
(280,'COA-2021-023','Air Conditioning Unit (1.5HP Split Type)',1,1,'2021-04-18',28775.06,3,NULL,1,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-19 09:00:00','2026-07-20 14:59:08'),
(281,'COA-2017-029','IP Desk Phone',7,1,'2017-08-09',39151.74,15,'Jose Salazar',1,'General Services Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-10 09:00:00','2026-07-17 18:12:48'),
(282,'COA-2021-024','Emergency Light Tower',10,1,'2021-06-28',73011.93,6,'Corazon Aguilar',NULL,'Accounting Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-01 09:00:00','2026-07-20 14:59:08'),
(283,'COA-2018-027','Backhoe Loader',6,1,'2018-02-19',2278732.20,17,'Elena Flores',1,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2018-02-21 09:00:00','2026-07-17 18:12:48'),
(284,'COA-2022-030','Nebulizer Machine',8,1,'2022-09-08',52889.33,17,'Pedro Castillo',1,'Disaster Risk Reduction and Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-08 09:00:00','2026-07-20 14:59:08'),
(285,'COA-2024-018','Executive Office Desk',3,5,'2024-03-25',14724.18,7,'Danilo Fernandez',5,'Treasury Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2024-03-27 09:00:00','2026-07-17 18:12:48'),
(286,'COA-2023-034','Refrigerator (2-Door)',1,1,'2023-09-26',24380.72,2,'Cecilia Ramos',1,'Office of the Vice Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-27 09:00:00','2026-07-17 18:12:48'),
(287,'COA-2020-019','Patrol Motorcycle',5,1,'2020-09-11',2022588.37,5,'Corazon Bautista',NULL,'Budget Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-13 09:00:00','2026-07-20 14:59:08'),
(288,'COA-2023-035','Fax Machine',4,1,'2023-11-21',21311.77,12,'Josefa Torres',NULL,'Municipal Health Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-23 09:00:00','2026-07-17 18:12:48'),
(289,'COA-2024-019','Steel Filing Cabinet (4-Drawer)',3,1,'2024-09-27',25448.09,3,'Francisco Villanueva',1,'Sangguniang Bayan Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-30 09:00:00','2026-07-17 18:12:48'),
(290,'COA-2017-030','Megaphone (Bullhorn)',7,1,'2017-01-24',34723.67,4,'Leonora Garcia',NULL,'Human Resource Management Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-25 09:00:00','2026-07-17 18:12:48'),
(291,'COA-2017-031','Water Tanker Truck',6,1,'2017-04-11',1490713.14,6,'Alfredo Domingo',1,'Accounting Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2017-04-12 09:00:00','2026-07-17 18:12:48'),
(292,'COA-2026-029','Document Scanner',2,1,'2026-03-21',44648.64,14,'Francisco Mendoza',NULL,'Municipal Agriculture Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-21 09:00:00','2026-07-20 14:59:08'),
(293,'COA-2026-030','Partition Divider Panel',3,1,'2026-04-27',24987.52,16,'Jose Ramos',NULL,'Information and Communications Technology Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2026-04-30 09:00:00','2026-07-20 14:59:08'),
(294,'COA-2023-036','Emergency Light Tower',10,1,'2023-07-06',33461.96,8,'Danilo Cruz',1,'Assessor\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-08 09:00:00','2026-07-17 18:12:48'),
(295,'COA-2016-021','Farm Tool Kit',9,1,'2016-02-17',92732.68,2,'Josefa Mendoza',1,'Office of the Vice Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-17 09:00:00','2026-07-17 18:12:48'),
(296,'COA-2025-028','Base Radio Station',7,1,'2025-02-28',5850.30,13,'Eduardo Pascual',1,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-02 09:00:00','2026-07-20 14:59:08'),
(297,'COA-2022-031','CCTV Camera (Outdoor)',7,1,'2022-04-01',2507.21,2,'Corazon Cruz',1,'Office of the Vice Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-04-02 09:00:00','2026-07-17 18:12:48'),
(298,'COA-2019-024','Bulletin Board (Cork, Framed)',4,1,'2019-09-21',47432.80,15,'Francisco Bautista',NULL,'General Services Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-21 09:00:00','2026-07-17 18:12:48'),
(299,'COA-2023-037','Hand Tractor',9,1,'2023-11-15',161798.81,12,'Alfredo Marquez',NULL,'Municipal Health Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-17 09:00:00','2026-07-20 14:59:08'),
(300,'COA-2017-032','Fax Machine',4,1,'2017-03-17',5883.02,11,'Imelda Navarro',1,'Municipal Planning and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-19 09:00:00','2026-07-17 18:12:48'),
(301,'COA-2022-032','Sprayer (Backpack, Motorized)',9,5,'2022-03-16',88737.49,2,'Gloria Mendoza',5,'Office of the Vice Mayor - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-16 09:00:00','2026-07-20 14:59:08'),
(302,'COA-2022-033','CCTV DVR/NVR Unit',7,1,'2022-10-30',34900.92,14,'Antonio Villanueva',1,'Municipal Agriculture Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-01 09:00:00','2026-07-17 18:12:48'),
(303,'COA-2023-038','Farm Tool Kit',9,5,'2023-12-25',115150.95,11,'Corazon Marquez',NULL,'Municipal Planning and Development Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-26 09:00:00','2026-07-20 14:59:08'),
(304,'COA-2023-039','Hand Tractor',9,1,'2023-12-19',102742.46,11,'Imelda Marquez',1,'Municipal Planning and Development Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2023-12-19 09:00:00','2026-07-20 14:59:08'),
(305,'COA-2017-033','Electric Fan (Stand Type)',1,1,'2017-08-18',37688.34,13,'Ernesto Mendoza',1,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-21 09:00:00','2026-07-20 14:59:08'),
(306,'COA-2017-034','Grass Cutter (Riding Type)',6,1,'2017-02-23',2823900.81,15,'Leonora Flores',1,'General Services Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2017-02-24 09:00:00','2026-07-17 18:12:48'),
(307,'COA-2024-020','CCTV DVR/NVR Unit',7,1,'2024-11-02',15787.79,14,'Juan Ocampo',NULL,'Municipal Agriculture Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-05 09:00:00','2026-07-20 14:59:08'),
(308,'COA-2024-021','Generator Set (25 kVA)',6,1,'2024-09-14',3098226.00,7,'Rosa Del Rosario',1,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-15 09:00:00','2026-07-17 18:12:48'),
(309,'COA-2022-034','Conference Table (8-Seater)',3,1,'2022-07-20',10059.08,6,'Pedro Reyes',NULL,'Accounting Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-22 09:00:00','2026-07-17 18:12:48'),
(310,'COA-2016-022','Emergency Light Tower',10,1,'2016-10-25',67814.39,12,'Rosa Rivera',1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-28 09:00:00','2026-07-17 18:12:48'),
(311,'COA-2020-020','Bulldozer',6,1,'2020-01-17',972569.06,11,'Ricardo Salazar',1,'Municipal Planning and Development Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-20 09:00:00','2026-07-20 14:59:08'),
(312,'COA-2016-023','Metal Detector (Handheld)',10,1,'2016-06-12',84366.39,8,'Divina Bautista',NULL,'Assessor\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-13 09:00:00','2026-07-20 14:59:08'),
(313,'COA-2021-025','Hand Tractor',9,1,'2021-06-16',162046.70,15,'Ricardo Santos',1,'General Services Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-16 09:00:00','2026-07-20 14:59:08'),
(314,'COA-2025-029','Paper Shredder (Heavy Duty)',4,1,'2025-05-15',15745.93,14,'Romeo Ocampo',1,'Municipal Agriculture Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-15 09:00:00','2026-07-20 14:59:08'),
(315,'COA-2016-024','Laser Printer (Monochrome)',2,1,'2016-08-10',68948.75,3,'Eduardo Flores',1,'Sangguniang Bayan Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-13 09:00:00','2026-07-17 18:12:48'),
(316,'COA-2024-022','Electric Fan (Stand Type)',1,1,'2024-06-23',39296.31,3,'Gloria Rivera',NULL,'Sangguniang Bayan Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-24 09:00:00','2026-07-17 18:12:48'),
(317,'COA-2017-035','Air Conditioning Unit (1.5HP Split Type)',1,1,'2017-10-02',9660.03,16,'Divina Gonzales',NULL,'Information and Communications Technology Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-05 09:00:00','2026-07-17 18:12:48'),
(318,'COA-2022-035','Concrete Mixer',6,1,'2022-03-17',1931948.78,1,'Juan Navarro',NULL,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-19 09:00:00','2026-07-20 14:59:08'),
(319,'COA-2026-031','Typewriter (Manual)',4,1,'2026-02-26',12979.17,14,'Alfredo Ramos',NULL,'Municipal Agriculture Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-26 09:00:00','2026-07-20 14:59:08'),
(320,'COA-2019-025','Weighing Scale (Digital)',8,1,'2019-04-05',31206.48,3,'Eduardo Salazar',1,'Sangguniang Bayan Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-05 09:00:00','2026-07-17 18:12:48'),
(321,'COA-2019-026','Wheelchair',8,1,'2019-09-06',83674.79,15,'Eduardo Aquino',NULL,'General Services Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-08 09:00:00','2026-07-17 18:12:48'),
(322,'COA-2017-036','Dump Truck',5,1,'2017-07-04',1732702.39,12,NULL,1,'Municipal Health Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2017-07-04 09:00:00','2026-07-20 14:59:08'),
(323,'COA-2018-028','Steel Filing Cabinet (4-Drawer)',3,1,'2018-12-14',25108.42,7,'Rodrigo Dela Cruz',1,'Treasury Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-16 09:00:00','2026-07-20 14:59:08'),
(324,'COA-2020-021','Autoclave Sterilizer',8,1,'2020-02-07',27961.84,5,'Norma Villanueva',1,'Budget Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-10 09:00:00','2026-07-20 12:47:01'),
(325,'COA-2024-023','Chainsaw (Rescue Type)',10,1,'2024-06-28',15054.47,6,'Eduardo Navarro',1,'Accounting Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2024-06-28 09:00:00','2026-07-17 18:12:48'),
(326,'COA-2023-040','Calculator (Desktop Printing)',4,1,'2023-07-01',35108.88,2,'Manuel Salazar',NULL,'Office of the Vice Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-03 09:00:00','2026-07-17 18:12:48'),
(327,'COA-2022-036','Motorcycle (Service Unit)',5,1,'2022-06-28',1447780.27,9,'Manuel Aquino',NULL,'Civil Registrar\'s Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-30 09:00:00','2026-07-20 14:59:08'),
(328,'COA-2021-026','Concrete Mixer',6,1,'2021-06-17',1724013.76,12,'Ricardo Garcia',1,'Municipal Health Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-19 09:00:00','2026-07-17 18:12:48'),
(329,'COA-2020-022','24-Port Network Switch',2,1,'2020-08-25',63179.94,8,'Josefa Salazar',1,'Assessor\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-25 09:00:00','2026-07-17 18:12:48'),
(330,'COA-2016-025','Swivel Office Chair',3,1,'2016-06-09',5657.95,17,NULL,NULL,'Disaster Risk Reduction and Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-11 09:00:00','2026-07-17 18:12:48'),
(331,'COA-2025-030','Inflatable Rescue Boat',10,1,'2025-09-22',17862.71,16,'Corazon Garcia',NULL,'Information and Communications Technology Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-24 09:00:00','2026-07-17 18:12:48'),
(332,'COA-2018-029','Autoclave Sterilizer',8,1,'2018-07-30',47177.23,3,'Carlos Rivera',NULL,'Sangguniang Bayan Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-01 09:00:00','2026-07-20 14:59:08'),
(333,'COA-2024-024','Hand Tractor',9,1,'2024-06-08',88615.53,17,'Corazon Gonzales',1,'Disaster Risk Reduction and Management Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2024-06-09 09:00:00','2026-07-20 14:59:08'),
(334,'COA-2024-025','Fax Machine',4,1,'2024-11-08',24732.10,16,'Gloria Marquez',NULL,'Information and Communications Technology Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2024-11-11 09:00:00','2026-07-20 14:59:08'),
(335,'COA-2016-026','Dump Truck',5,1,'2016-01-23',1751379.94,7,'Ricardo Bautista',1,'Treasury Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-01-25 09:00:00','2026-07-17 18:12:48'),
(336,'COA-2017-037','Water Tanker Truck',6,1,'2017-09-25',2206991.41,4,'Leonora Gonzales',1,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-26 09:00:00','2026-07-20 14:59:08'),
(337,'COA-2018-030','Water Pump (Irrigation)',9,5,'2018-01-02',101441.85,16,'Luz Navarro',5,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-04 09:00:00','2026-07-20 14:59:08'),
(338,'COA-2018-031','Steel Locker Cabinet',3,1,'2018-05-28',22662.88,4,'Imelda Marquez',1,'Human Resource Management Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-29 09:00:00','2026-07-20 14:59:08'),
(339,'COA-2016-027','IP Desk Phone',7,1,'2016-09-19',11925.24,3,'Maria Ocampo',NULL,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2016-09-20 09:00:00','2026-07-17 18:12:48'),
(340,'COA-2016-028','Stretcher (Foldable)',8,1,'2016-02-13',102292.26,15,NULL,1,'General Services Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-13 09:00:00','2026-07-17 18:12:48'),
(341,'COA-2018-032','Electric Fan (Stand Type)',1,1,'2018-09-06',53721.41,12,'Ramon Domingo',NULL,'Municipal Health Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-09 09:00:00','2026-07-17 18:12:48'),
(342,'COA-2019-027','Water Pump (Irrigation)',9,1,'2019-11-24',110523.14,12,'Gloria Domingo',1,'Municipal Health Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-11-25 09:00:00','2026-07-17 18:12:48'),
(343,'COA-2019-028','Hand Tractor',9,5,'2019-10-24',172359.20,10,NULL,5,'Municipal Engineering Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-25 09:00:00','2026-07-17 18:12:48'),
(344,'COA-2026-032','Digital Blood Pressure Monitor',8,1,'2026-01-20',58613.46,15,'Manuel Fernandez',1,'General Services Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2026-01-22 09:00:00','2026-07-17 18:12:48'),
(345,'COA-2017-038','Fax Machine',4,1,'2017-01-15',44769.27,10,'Jose Gonzales',1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-16 09:00:00','2026-07-20 14:59:08'),
(346,'COA-2024-026','Calculator (Desktop Printing)',4,1,'2024-04-07',17561.41,16,'Ramon Torres',1,'Information and Communications Technology Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-09 09:00:00','2026-07-17 18:12:48'),
(347,'COA-2024-027','Digital Blood Pressure Monitor',8,1,'2024-07-27',101989.26,1,'Antonio Salazar',1,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-30 09:00:00','2026-07-20 14:59:08'),
(348,'COA-2016-029','Chainsaw (Rescue Type)',10,1,'2016-08-09',76332.10,5,'Cecilia Reyes',1,'Budget Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-10 09:00:00','2026-07-20 14:59:08'),
(349,'COA-2016-030','Generator Set (25 kVA)',6,1,'2016-02-18',950644.30,1,'Antonio Aquino',NULL,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-18 09:00:00','2026-07-17 18:12:48'),
(350,'COA-2020-023','Visitor\'s Chair (Stackable)',3,2,'2020-10-02',19979.10,16,'Leonora Domingo',NULL,'Information and Communications Technology Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-03 09:00:00','2026-07-20 14:59:08'),
(351,'COA-2025-031','Fax Machine',4,1,'2025-08-08',15155.92,14,'Norma Garcia',NULL,'Municipal Agriculture Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-08 09:00:00','2026-07-17 18:12:48'),
(352,'COA-2019-029','Bulldozer',6,1,'2019-05-13',1952094.59,16,'Manuel Bautista',1,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-05-14 09:00:00','2026-07-20 14:59:08'),
(353,'COA-2018-033','Nebulizer Machine',8,1,'2018-11-30',44196.33,11,'Divina Ramos',NULL,'Municipal Planning and Development Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-11-30 09:00:00','2026-07-17 18:12:48'),
(354,'COA-2024-028','Binding Machine',4,1,'2024-10-01',25016.76,6,'Josefa Ocampo',1,'Accounting Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-04 09:00:00','2026-07-17 18:12:48'),
(355,'COA-2023-041','Grass Cutter (Riding Type)',6,1,'2023-01-29',1979167.09,14,'Jose Santos',1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-30 09:00:00','2026-07-17 18:12:48'),
(356,'COA-2024-029','Thermal Scanner',8,1,'2024-05-21',50557.70,12,'Juan Garcia',1,'Municipal Health Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-24 09:00:00','2026-07-20 14:59:08'),
(357,'COA-2022-037','Desktop Computer Set (Core i5)',2,1,'2022-02-24',9056.46,16,'Ernesto Santos',1,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-26 09:00:00','2026-07-17 18:12:48'),
(358,'COA-2023-042','Service Pick-up Truck',5,1,'2023-01-10',679734.94,15,'Juan Reyes',1,'General Services Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-10 09:00:00','2026-07-17 18:12:48'),
(359,'COA-2023-043','Oxygen Tank with Regulator',8,1,'2023-10-28',71513.46,5,'Norma Fernandez',1,'Budget Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-29 09:00:00','2026-07-20 12:47:01'),
(360,'COA-2019-030','24-Port Network Switch',2,1,'2019-06-15',39151.90,15,'Juan Dela Cruz',1,'General Services Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-17 09:00:00','2026-07-20 14:59:08'),
(361,'COA-2016-031','Autoclave Sterilizer',8,1,'2016-02-07',96058.83,10,'Divina Dela Cruz',1,'Municipal Engineering Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-08 09:00:00','2026-07-17 18:12:48'),
(362,'COA-2018-034','IP Desk Phone',7,1,'2018-06-22',5866.41,13,'Ricardo Cruz',1,'Municipal Social Welfare and Development Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-06-22 09:00:00','2026-07-20 14:59:08'),
(363,'COA-2023-044','Ambulance Unit',5,1,'2023-02-21',1531026.47,4,'Corazon Salazar',1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-23 09:00:00','2026-07-20 14:59:08'),
(364,'COA-2018-035','Weighing Scale (Digital)',8,1,'2018-08-11',19356.02,1,'Antonio Aguilar',1,'Office of the Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-08-13 09:00:00','2026-07-17 18:12:48'),
(365,'COA-2024-030','Vacuum Cleaner',1,1,'2024-09-12',6247.70,9,'Carlos Ramos',NULL,'Civil Registrar\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-15 09:00:00','2026-07-17 18:12:48'),
(366,'COA-2021-027','Refrigerator (2-Door)',1,1,'2021-03-02',29859.80,7,NULL,NULL,'Treasury Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-02 09:00:00','2026-07-20 14:59:08'),
(367,'COA-2017-039','Water Pump (Irrigation)',9,2,'2017-05-15',116198.78,17,'Romeo Reyes',2,'Disaster Risk Reduction and Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-16 09:00:00','2026-07-17 18:12:48'),
(368,'COA-2016-032','Bulletin Board (Cork, Framed)',4,1,'2016-06-21',45681.21,1,'Ernesto Santos',NULL,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-21 09:00:00','2026-07-17 18:12:48'),
(369,'COA-2023-045','Water Dispenser (Hot & Cold)',1,1,'2023-03-25',39319.73,12,'Pedro Salazar',NULL,'Municipal Health Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-27 09:00:00','2026-07-17 18:12:48'),
(370,'COA-2020-024','Water Dispenser (Hot & Cold)',1,1,'2020-01-07',15661.55,13,'Danilo Pascual',1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-09 09:00:00','2026-07-17 18:12:48'),
(371,'COA-2016-033','Motorcycle (Service Unit)',5,1,'2016-10-09',721294.59,6,'Ramon Gonzales',NULL,'Accounting Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-12 09:00:00','2026-07-20 14:59:08'),
(372,'COA-2019-031','Generator Set (25 kVA)',6,1,'2019-08-06',530524.01,8,NULL,1,'Assessor\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-07 09:00:00','2026-07-17 18:12:48'),
(373,'COA-2017-040','Grass Cutter (Riding Type)',6,1,'2017-01-29',2227839.44,4,'Pedro Mendoza',NULL,'Human Resource Management Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-31 09:00:00','2026-07-20 14:59:08'),
(374,'COA-2016-034','Water Pump (Irrigation)',9,1,'2016-07-20',110450.81,9,'Gloria Torres',1,'Civil Registrar\'s Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-21 09:00:00','2026-07-20 14:59:08'),
(375,'COA-2024-031','CCTV DVR/NVR Unit',7,1,'2024-11-27',4977.75,12,'Ricardo Reyes',1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-27 09:00:00','2026-07-17 18:12:48'),
(376,'COA-2018-036','CCTV Camera (Outdoor)',7,1,'2018-03-02',30417.25,7,'Rosa Gonzales',1,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-03 09:00:00','2026-07-17 18:12:48'),
(377,'COA-2024-032','Laser Printer (Monochrome)',2,1,'2024-11-19',49897.31,6,'Imelda Mendoza',NULL,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-19 09:00:00','2026-07-17 18:12:48'),
(378,'COA-2024-033','Generator Set (25 kVA)',6,1,'2024-07-27',1577176.01,14,'Corazon Flores',1,'Municipal Agriculture Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-28 09:00:00','2026-07-17 18:12:48'),
(379,'COA-2024-034','Handheld Two-Way Radio',7,1,'2024-02-22',44275.65,1,'Ricardo Garcia',1,'Office of the Mayor - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-02-24 09:00:00','2026-07-20 14:59:08'),
(380,'COA-2022-038','Motorcycle (Service Unit)',5,1,'2022-03-28',2070364.29,17,'Maria Pascual',1,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-28 09:00:00','2026-07-20 14:59:08'),
(381,'COA-2022-039','All-in-One Inkjet Printer',2,1,'2022-05-19',64272.74,13,'Divina Salazar',1,'Municipal Social Welfare and Development Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-20 09:00:00','2026-07-20 14:59:08'),
(382,'COA-2016-035','Electric Fan (Stand Type)',1,1,'2016-11-17',50898.25,13,'Romeo Aguilar',NULL,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-17 09:00:00','2026-07-17 18:12:48'),
(383,'COA-2019-032','CCTV Camera (Outdoor)',7,1,'2019-06-02',4250.25,2,'Pedro Castillo',NULL,'Office of the Vice Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-02 09:00:00','2026-07-17 18:12:48'),
(384,'COA-2017-041','Rescue Rope Kit',10,1,'2017-01-03',42170.02,17,'Pedro Garcia',1,'Disaster Risk Reduction and Management Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-01-03 09:00:00','2026-07-17 18:12:48'),
(385,'COA-2021-028','LCD/LED Monitor 24\"',2,1,'2021-08-17',67358.36,13,'Pedro Salazar',NULL,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-17 09:00:00','2026-07-17 18:12:48'),
(386,'COA-2018-037','Fax Machine',4,1,'2018-12-26',23051.52,3,NULL,1,'Sangguniang Bayan Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-27 09:00:00','2026-07-20 14:59:08'),
(387,'COA-2017-042','Electric Kettle',1,1,'2017-11-24',34851.60,10,NULL,1,'Municipal Engineering Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-24 09:00:00','2026-07-20 14:59:08'),
(388,'COA-2024-035','Desktop Computer Set (Core i5)',2,1,'2024-04-17',25957.77,4,'Pedro Villanueva',1,'Human Resource Management Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-19 09:00:00','2026-07-20 14:59:08'),
(389,'COA-2022-040','Binding Machine',4,1,'2022-02-16',37025.60,7,'Pedro Marquez',1,'Treasury Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-19 09:00:00','2026-07-20 14:59:08'),
(390,'COA-2016-036','Inflatable Rescue Boat',10,1,'2016-08-05',62892.48,9,'Manuel Del Rosario',1,'Civil Registrar\'s Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-07 09:00:00','2026-07-20 14:59:08'),
(391,'COA-2020-025','CCTV Camera (Outdoor)',7,1,'2020-04-08',44006.01,8,'Antonio Salazar',NULL,'Assessor\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2020-04-10 09:00:00','2026-07-17 18:12:48'),
(392,'COA-2019-033','Sprayer (Backpack, Motorized)',9,2,'2019-09-28',134884.96,10,'Imelda Aquino',NULL,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-29 09:00:00','2026-07-20 14:59:08'),
(393,'COA-2022-041','IP Desk Phone',7,1,'2022-03-23',12087.26,1,'Manuel Del Rosario',1,'Office of the Mayor - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-03-23 09:00:00','2026-07-17 18:12:48'),
(394,'COA-2018-038','Typewriter (Manual)',4,1,'2018-09-11',29440.83,14,'Corazon Castillo',NULL,'Municipal Agriculture Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-13 09:00:00','2026-07-20 14:59:08'),
(395,'COA-2026-033','Service Pick-up Truck',5,1,'2026-03-14',1202612.52,17,NULL,1,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-15 09:00:00','2026-07-17 18:12:48'),
(396,'COA-2024-036','Bookshelf (Wooden, 5-Tier)',3,2,'2024-08-01',26960.06,1,'Norma Fernandez',2,'Office of the Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-04 09:00:00','2026-07-20 14:59:08'),
(397,'COA-2018-039','Metal Detector (Handheld)',10,1,'2018-08-03',4425.86,8,'Ernesto Salazar',NULL,'Assessor\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-06 09:00:00','2026-07-17 18:12:48'),
(398,'COA-2018-040','Visitor\'s Chair (Stackable)',3,1,'2018-03-02',12150.19,6,NULL,1,'Accounting Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-02 09:00:00','2026-07-17 18:12:48'),
(399,'COA-2023-046','Nebulizer Machine',8,1,'2023-09-18',104212.83,16,NULL,1,'Information and Communications Technology Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-20 09:00:00','2026-07-17 18:12:48'),
(400,'COA-2023-047','Metal Detector (Handheld)',10,1,'2023-03-12',75183.55,17,'Francisco Pascual',1,'Disaster Risk Reduction and Management Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-14 09:00:00','2026-07-17 18:12:48'),
(401,'COA-2019-034','Water Cooler/Dispenser',1,1,'2019-04-07',23397.09,7,'Alfredo Villanueva',1,'Treasury Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-08 09:00:00','2026-07-20 14:59:08'),
(402,'COA-2017-043','Laser Printer (Monochrome)',2,1,'2017-04-08',67741.03,17,NULL,1,'Disaster Risk Reduction and Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-09 09:00:00','2026-07-17 18:12:48'),
(403,'COA-2017-044','Binding Machine',4,1,'2017-01-04',23092.64,15,'Danilo Mendoza',NULL,'General Services Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-07 09:00:00','2026-07-17 18:12:48'),
(404,'COA-2020-026','Seedling Tray Set',9,2,'2020-03-31',11249.42,6,'Antonio Navarro',2,'Accounting Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-03 09:00:00','2026-07-17 18:12:48'),
(405,'COA-2023-048','Oxygen Tank with Regulator',8,1,'2023-01-09',15430.15,10,'Carlos Dela Cruz',NULL,'Municipal Engineering Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-09 09:00:00','2026-07-17 18:12:48'),
(406,'COA-2018-041','Thermal Scanner',8,1,'2018-06-07',55268.01,8,'Corazon Cruz',NULL,'Assessor\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-06-08 09:00:00','2026-07-17 18:12:48'),
(407,'COA-2016-037','Water Dispenser (Hot & Cold)',1,1,'2016-05-30',47326.04,12,'Alfredo Cruz',1,'Municipal Health Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-02 09:00:00','2026-07-20 14:59:08'),
(408,'COA-2021-029','Metal Detector (Handheld)',10,1,'2021-02-08',55843.87,6,NULL,NULL,'Accounting Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-08 09:00:00','2026-07-20 14:59:08'),
(409,'COA-2021-030','Laser Printer (Monochrome)',2,1,'2021-04-12',16517.81,10,NULL,1,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-14 09:00:00','2026-07-17 18:12:48'),
(410,'COA-2021-031','Farm Tool Kit',9,5,'2021-06-04',168331.88,3,NULL,5,'Sangguniang Bayan Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-07 09:00:00','2026-07-20 14:59:08'),
(411,'COA-2021-032','Metal Detector (Handheld)',10,1,'2021-10-29',60762.76,16,'Rosa Cruz',NULL,'Information and Communications Technology Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-11-01 09:00:00','2026-07-20 14:59:08'),
(412,'COA-2020-027','Fire Extinguisher (10lbs)',10,1,'2020-08-22',33042.68,14,'Rodrigo Torres',1,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-25 09:00:00','2026-07-17 18:12:48'),
(413,'COA-2023-049','Electric Kettle',1,1,'2023-09-10',20421.48,4,'Corazon Dela Cruz',1,'Human Resource Management Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2023-09-13 09:00:00','2026-07-17 18:12:48'),
(414,'COA-2023-050','Thermal Scanner',8,1,'2023-01-13',107208.91,5,'Antonio Pascual',1,'Budget Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-14 09:00:00','2026-07-20 12:47:01'),
(415,'COA-2022-042','Electric Kettle',1,1,'2022-06-23',44475.61,7,NULL,1,'Treasury Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-06-25 09:00:00','2026-07-17 18:12:48'),
(416,'COA-2022-043','CCTV Camera (Outdoor)',7,1,'2022-05-27',19056.57,6,'Leonora Villanueva',1,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-30 09:00:00','2026-07-20 14:59:08'),
(417,'COA-2021-033','Multi-Purpose Van',5,1,'2021-11-20',756272.31,7,'Maria Torres',1,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-11-23 09:00:00','2026-07-17 18:12:48'),
(418,'COA-2024-037','Water Pump (Irrigation)',9,1,'2024-09-11',139313.47,10,'Ricardo Del Rosario',1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-13 09:00:00','2026-07-17 18:12:48'),
(419,'COA-2019-035','Water Cooler/Dispenser',1,1,'2019-09-27',49182.26,3,'Ernesto Del Rosario',1,'Sangguniang Bayan Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-09-27 09:00:00','2026-07-17 18:12:48'),
(420,'COA-2019-036','Binding Machine',4,1,'2019-03-19',36001.10,7,'Imelda Bautista',1,'Treasury Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-19 09:00:00','2026-07-20 14:59:08'),
(421,'COA-2019-037','Road Roller',6,1,'2019-01-15',3038341.78,11,'Eduardo Flores',1,'Municipal Planning and Development Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-01-16 09:00:00','2026-07-17 18:12:48'),
(422,'COA-2021-034','Executive Office Desk',3,1,'2021-04-12',11480.47,1,'Manuel Mendoza',1,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-14 09:00:00','2026-07-17 18:12:48'),
(423,'COA-2024-038','Bulletin Board (Cork, Framed)',4,1,'2024-06-22',38202.94,3,'Divina Marquez',NULL,'Sangguniang Bayan Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-22 09:00:00','2026-07-20 14:59:08'),
(424,'COA-2026-034','Life Vest',10,1,'2026-03-28',38463.15,9,'Imelda Castillo',1,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-31 09:00:00','2026-07-17 18:12:48'),
(425,'COA-2021-035','Backhoe Loader',6,1,'2021-09-11',1506205.05,5,'Ana Castillo',1,'Budget Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-14 09:00:00','2026-07-20 14:59:08'),
(426,'COA-2021-036','Sprayer (Backpack, Motorized)',9,1,'2021-05-29',63636.05,6,'Eduardo Aguilar',1,'Accounting Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-31 09:00:00','2026-07-17 18:12:48'),
(427,'COA-2017-045','Chainsaw (Rescue Type)',10,1,'2017-04-13',57435.02,16,'Ana Pascual',1,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-16 09:00:00','2026-07-17 18:12:48'),
(428,'COA-2023-051','Generator Set (25 kVA)',6,1,'2023-03-26',525224.33,16,'Pedro Navarro',1,'Information and Communications Technology Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-29 09:00:00','2026-07-17 18:12:48'),
(429,'COA-2019-038','Binding Machine',4,1,'2019-05-12',59947.10,11,NULL,NULL,'Municipal Planning and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-13 09:00:00','2026-07-17 18:12:48'),
(430,'COA-2026-035','Electric Fan (Stand Type)',1,1,'2026-02-07',2544.27,12,'Carmen Bautista',1,'Municipal Health Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-10 09:00:00','2026-07-17 18:12:48'),
(431,'COA-2022-044','Base Radio Station',7,1,'2022-02-10',30655.72,14,'Carlos Gonzales',NULL,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-13 09:00:00','2026-07-17 18:12:48'),
(432,'COA-2023-052','Electric Fan (Stand Type)',1,1,'2023-04-09',10059.78,3,NULL,NULL,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-10 09:00:00','2026-07-20 14:59:08'),
(433,'COA-2022-045','Rescue Rope Kit',10,1,'2022-12-27',44258.68,14,'Alfredo Pascual',NULL,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-28 09:00:00','2026-07-17 18:12:48'),
(434,'COA-2020-028','Seedling Tray Set',9,5,'2020-08-09',68270.21,9,NULL,5,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-12 09:00:00','2026-07-17 18:12:48'),
(435,'COA-2021-037','Seedling Tray Set',9,1,'2021-03-19',95872.47,9,'Elena Salazar',NULL,'Civil Registrar\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-19 09:00:00','2026-07-17 18:12:48'),
(436,'COA-2021-038','Water Cooler/Dispenser',1,1,'2021-02-02',32633.18,16,'Carmen Villanueva',NULL,'Information and Communications Technology Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-02 09:00:00','2026-07-17 18:12:48'),
(437,'COA-2022-046','Digital Blood Pressure Monitor',8,1,'2022-06-04',79273.91,6,'Norma Cruz',1,'Accounting Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-07 09:00:00','2026-07-17 18:12:48'),
(438,'COA-2025-032','Multi-Purpose Van',5,1,'2025-08-14',474855.27,9,'Rosa Navarro',1,'Civil Registrar\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-14 09:00:00','2026-07-17 18:12:48'),
(439,'COA-2019-039','Hand Tractor',9,1,'2019-11-05',108613.53,2,'Alfredo Salazar',1,'Office of the Vice Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-05 09:00:00','2026-07-17 18:12:48'),
(440,'COA-2023-053','Bulldozer',6,1,'2023-03-15',2503129.20,2,'Rosa Pascual',1,'Office of the Vice Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-17 09:00:00','2026-07-20 14:59:08'),
(441,'COA-2018-042','Base Radio Station',7,1,'2018-12-11',25043.79,16,'Luz Pascual',NULL,'Information and Communications Technology Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-14 09:00:00','2026-07-20 14:59:08'),
(442,'COA-2019-040','Multi-Purpose Van',5,1,'2019-01-12',1854053.63,11,'Eduardo Domingo',1,'Municipal Planning and Development Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-14 09:00:00','2026-07-20 14:59:08'),
(443,'COA-2022-047','Executive Office Desk',3,1,'2022-02-21',23489.28,11,'Ana Rivera',1,'Municipal Planning and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-21 09:00:00','2026-07-17 18:12:48'),
(444,'COA-2022-048','Refrigerator (2-Door)',1,1,'2022-09-21',39673.94,7,'Leonora Cruz',1,'Treasury Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-23 09:00:00','2026-07-20 14:59:08'),
(445,'COA-2019-041','Partition Divider Panel',3,1,'2019-04-21',18319.32,9,NULL,1,'Civil Registrar\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-22 09:00:00','2026-07-17 18:12:48'),
(446,'COA-2020-029','Ambulance Unit',5,1,'2020-04-16',1032145.79,2,'Alfredo Ramos',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-17 09:00:00','2026-07-20 14:59:08'),
(447,'COA-2018-043','Steel Filing Cabinet (4-Drawer)',3,2,'2018-06-13',20372.73,14,'Jose Santos',2,'Municipal Agriculture Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2018-06-13 09:00:00','2026-07-20 14:59:08'),
(448,'COA-2017-046','CCTV DVR/NVR Unit',7,1,'2017-09-12',16517.81,9,'Juan Rivera',1,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-12 09:00:00','2026-07-17 18:12:48'),
(449,'COA-2017-047','CCTV Camera (Outdoor)',7,1,'2017-05-11',25250.42,16,NULL,1,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-11 09:00:00','2026-07-17 18:12:48'),
(450,'COA-2025-033','Water Tanker Truck',6,1,'2025-06-07',2517291.28,3,'Carlos Mendoza',1,'Sangguniang Bayan Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-06-08 09:00:00','2026-07-17 18:12:48'),
(451,'COA-2021-039','Laptop Computer (Business Series)',2,1,'2021-06-15',76046.70,12,'Carlos Garcia',1,'Municipal Health Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-18 09:00:00','2026-07-17 18:12:48'),
(452,'COA-2021-040','Patrol Motorcycle',5,1,'2021-12-27',1870611.65,16,NULL,1,'Information and Communications Technology Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-12-27 09:00:00','2026-07-17 18:12:48'),
(453,'COA-2025-034','UPS (Uninterruptible Power Supply)',2,1,'2025-01-18',42752.89,7,'Leonora Gonzales',1,'Treasury Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2025-01-20 09:00:00','2026-07-20 14:59:08'),
(454,'COA-2016-038','Typewriter (Manual)',4,1,'2016-02-28',42225.01,5,NULL,1,'Budget Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-29 09:00:00','2026-07-20 12:47:01'),
(455,'COA-2016-039','Emergency Light Tower',10,1,'2016-09-15',20845.63,8,'Alfredo Ocampo',NULL,'Assessor\'s Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-16 09:00:00','2026-07-20 14:59:08'),
(456,'COA-2019-042','Refrigerator (2-Door)',1,1,'2019-10-06',8839.14,6,'Teresa Mendoza',NULL,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-08 09:00:00','2026-07-20 14:59:08'),
(457,'COA-2016-040','PABX Telephone System',7,1,'2016-03-05',5930.71,6,'Gloria Santos',1,'Accounting Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-06 09:00:00','2026-07-20 14:59:08'),
(458,'COA-2021-041','Ambulance Unit',5,1,'2021-01-18',868694.08,17,'Danilo Reyes',NULL,'Disaster Risk Reduction and Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-19 09:00:00','2026-07-20 14:59:08'),
(459,'COA-2018-044','Refrigerator (2-Door)',1,1,'2018-02-25',54296.69,8,NULL,NULL,'Assessor\'s Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-26 09:00:00','2026-07-20 14:59:08'),
(460,'COA-2018-045','Service Vehicle (Sedan)',5,1,'2018-03-04',1844072.70,2,'Gloria Salazar',1,'Office of the Vice Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-05 09:00:00','2026-07-20 14:59:08'),
(461,'COA-2016-041','Backhoe Loader',6,1,'2016-06-26',2460188.12,15,NULL,NULL,'General Services Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-26 09:00:00','2026-07-17 18:12:48'),
(462,'COA-2018-046','Generator Set (25 kVA)',6,1,'2018-03-25',2279029.76,14,'Ernesto Bautista',NULL,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2018-03-27 09:00:00','2026-07-17 18:12:48'),
(463,'COA-2017-048','Air Conditioning Unit (1.5HP Split Type)',1,1,'2017-08-16',51214.07,14,'Manuel Aquino',1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2017-08-17 09:00:00','2026-07-17 18:12:48'),
(464,'COA-2017-049','Patrol Motorcycle',5,1,'2017-03-31',1264685.02,5,'Ernesto Castillo',1,'Budget Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-01 09:00:00','2026-07-20 12:47:01'),
(465,'COA-2016-042','Sprayer (Backpack, Motorized)',9,5,'2016-12-20',89846.16,8,NULL,NULL,'Assessor\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-20 09:00:00','2026-07-20 14:59:08'),
(466,'COA-2025-035','CCTV Camera (Outdoor)',7,1,'2025-12-31',42715.73,8,NULL,1,'Assessor\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-03 09:00:00','2026-07-20 14:59:08'),
(467,'COA-2025-036','Megaphone (Bullhorn)',7,1,'2025-01-29',32107.77,16,'Josefa Flores',1,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-29 09:00:00','2026-07-17 18:12:48'),
(468,'COA-2021-042','Wireless Router',2,1,'2021-05-19',19620.62,1,'Eduardo Ocampo',NULL,'Office of the Mayor - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-05-22 09:00:00','2026-07-17 18:12:48'),
(469,'COA-2024-039','Megaphone (Bullhorn)',7,1,'2024-11-09',18242.87,6,'Rodrigo Dela Cruz',NULL,'Accounting Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-12 09:00:00','2026-07-17 18:12:48'),
(470,'COA-2024-040','Metal Detector (Handheld)',10,1,'2024-10-31',9529.19,7,NULL,1,'Treasury Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-03 09:00:00','2026-07-20 14:59:08'),
(471,'COA-2017-050','Generator Set (25 kVA)',6,1,'2017-12-18',1942552.81,12,'Danilo Torres',NULL,'Municipal Health Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-20 09:00:00','2026-07-20 14:59:08'),
(472,'COA-2019-043','Laminating Machine',4,1,'2019-08-05',58671.85,8,'Teresa Ramos',1,'Assessor\'s Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-08-07 09:00:00','2026-07-17 18:12:48'),
(473,'COA-2023-054','UPS (Uninterruptible Power Supply)',2,1,'2023-12-17',59908.05,16,'Luz Pascual',NULL,'Information and Communications Technology Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-20 09:00:00','2026-07-17 18:12:48'),
(474,'COA-2016-043','Autoclave Sterilizer',8,1,'2016-11-24',107906.58,3,'Jose Bautista',1,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-27 09:00:00','2026-07-17 18:12:48'),
(475,'COA-2023-055','Motorcycle (Service Unit)',5,1,'2023-08-27',2080512.58,14,'Teresa Pascual',NULL,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-27 09:00:00','2026-07-20 14:59:08'),
(476,'COA-2022-049','Bulldozer',6,1,'2022-06-28',2218917.43,14,'Josefa Navarro',NULL,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-01 09:00:00','2026-07-17 18:12:48'),
(477,'COA-2021-043','Multi-Purpose Van',5,1,'2021-06-06',2148767.08,8,'Maria Garcia',1,'Assessor\'s Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-06 09:00:00','2026-07-20 14:59:08'),
(478,'COA-2017-051','Visitor\'s Chair (Stackable)',3,1,'2017-10-22',2302.86,5,'Pedro Pascual',NULL,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-22 09:00:00','2026-07-20 12:47:01'),
(479,'COA-2021-044','Wheelchair',8,1,'2021-12-25',15896.57,6,'Gloria Salazar',1,'Accounting Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-27 09:00:00','2026-07-20 14:59:08'),
(480,'COA-2026-036','Multi-Purpose Van',5,1,'2026-01-17',2146809.73,16,'Eduardo Del Rosario',1,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-17 09:00:00','2026-07-20 14:59:08'),
(481,'COA-2023-056','Refrigerator (2-Door)',1,1,'2023-08-09',18674.32,5,'Alfredo Flores',1,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-09 09:00:00','2026-07-20 12:47:01'),
(482,'COA-2016-044','Service Vehicle (Sedan)',5,1,'2016-04-02',1392221.51,7,'Imelda Santos',1,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-04-02 09:00:00','2026-07-17 18:12:48'),
(483,'COA-2024-041','Megaphone (Bullhorn)',7,1,'2024-01-11',20674.72,5,'Juan Villanueva',1,'Budget Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-13 09:00:00','2026-07-20 14:59:08'),
(484,'COA-2019-044','Base Radio Station',7,1,'2019-03-28',36741.09,15,NULL,1,'General Services Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-31 09:00:00','2026-07-20 14:59:08'),
(485,'COA-2016-045','Seedling Tray Set',9,2,'2016-09-27',19111.12,11,'Gloria Ramos',2,'Municipal Planning and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-30 09:00:00','2026-07-17 18:12:48'),
(486,'COA-2016-046','Patrol Motorcycle',5,1,'2016-06-21',1895934.53,16,'Luz Salazar',1,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-22 09:00:00','2026-07-17 18:12:48'),
(487,'COA-2023-057','Wheelchair',8,1,'2023-05-02',50933.08,4,'Danilo Fernandez',NULL,'Human Resource Management Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-05-03 09:00:00','2026-07-17 18:12:48'),
(488,'COA-2022-050','Inflatable Rescue Boat',10,1,'2022-07-08',54598.44,12,NULL,1,'Municipal Health Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-08 09:00:00','2026-07-20 14:59:08'),
(489,'COA-2017-052','Life Vest',10,1,'2017-08-21',44877.09,2,'Carmen Mendoza',1,'Office of the Vice Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-22 09:00:00','2026-07-20 14:59:08'),
(490,'COA-2018-047','Laser Printer (Monochrome)',2,1,'2018-03-04',66645.77,17,'Rosa Gonzales',1,'Disaster Risk Reduction and Management Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-07 09:00:00','2026-07-20 14:59:08'),
(491,'COA-2025-037','Laser Printer (Monochrome)',2,1,'2025-03-26',8006.02,12,'Carmen Salazar',1,'Municipal Health Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-26 09:00:00','2026-07-20 14:59:08'),
(492,'COA-2025-038','Seedling Tray Set',9,5,'2025-06-27',127449.75,17,'Teresa Pascual',5,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-06-29 09:00:00','2026-07-20 14:59:08'),
(493,'COA-2024-042','Nebulizer Machine',8,1,'2024-07-24',21906.55,17,'Norma Bautista',1,'Disaster Risk Reduction and Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-26 09:00:00','2026-07-17 18:12:48'),
(494,'COA-2016-047','Handheld Two-Way Radio',7,1,'2016-11-14',35424.42,4,'Maria Torres',1,'Human Resource Management Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-11-17 09:00:00','2026-07-17 18:12:48'),
(495,'COA-2016-048','Multi-Purpose Van',5,1,'2016-09-28',1618276.24,2,'Divina Bautista',1,'Office of the Vice Mayor - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-28 09:00:00','2026-07-20 14:59:08'),
(496,'COA-2019-045','Service Pick-up Truck',5,1,'2019-12-13',1946491.64,12,'Corazon Flores',NULL,'Municipal Health Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-14 09:00:00','2026-07-17 18:12:48'),
(497,'COA-2024-043','Steel Filing Cabinet (4-Drawer)',3,1,'2024-02-19',25868.79,1,NULL,1,'Office of the Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-22 09:00:00','2026-07-17 18:12:48'),
(498,'COA-2018-048','CCTV Camera (Outdoor)',7,1,'2018-05-27',12171.05,14,'Antonio Bautista',1,'Municipal Agriculture Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2018-05-29 09:00:00','2026-07-20 14:59:08'),
(499,'COA-2020-030','Wheelchair',8,1,'2020-04-25',55648.07,4,'Imelda Pascual',NULL,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-26 09:00:00','2026-07-20 14:59:08'),
(500,'COA-2018-049','Digital Blood Pressure Monitor',8,1,'2018-01-04',119848.71,12,'Ana Domingo',1,'Municipal Health Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-05 09:00:00','2026-07-20 14:59:08'),
(501,'COA-2020-031','Visitor\'s Chair (Stackable)',3,1,'2020-01-29',6567.06,3,'Manuel Bautista',1,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-01 09:00:00','2026-07-17 18:12:48'),
(502,'COA-2021-045','CCTV DVR/NVR Unit',7,1,'2021-05-02',28134.53,12,'Josefa Rivera',1,'Municipal Health Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-03 09:00:00','2026-07-20 14:59:08'),
(503,'COA-2024-044','Electric Fan (Stand Type)',1,1,'2024-04-10',46091.40,4,'Juan Mendoza',NULL,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-12 09:00:00','2026-07-17 18:12:48'),
(504,'COA-2024-045','Sprayer (Backpack, Motorized)',9,1,'2024-11-21',55313.86,16,'Ricardo Ramos',1,'Information and Communications Technology Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-23 09:00:00','2026-07-20 14:59:08'),
(505,'COA-2021-046','24-Port Network Switch',2,1,'2021-01-17',73524.19,13,'Maria Reyes',1,'Municipal Social Welfare and Development Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-19 09:00:00','2026-07-20 14:59:08'),
(506,'COA-2024-046','Handheld Two-Way Radio',7,1,'2024-07-26',26676.35,16,'Cecilia Del Rosario',1,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-29 09:00:00','2026-07-20 14:59:08'),
(507,'COA-2024-047','IP Desk Phone',7,1,'2024-08-05',16120.52,12,'Maria Garcia',1,'Municipal Health Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2024-08-06 09:00:00','2026-07-20 14:59:08'),
(508,'COA-2019-046','Backhoe Loader',6,1,'2019-12-09',2234534.02,14,'Rodrigo Villanueva',1,'Municipal Agriculture Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-12-12 09:00:00','2026-07-17 18:12:48'),
(509,'COA-2022-051','Bookshelf (Wooden, 5-Tier)',3,1,'2022-01-14',13552.37,1,NULL,1,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-14 09:00:00','2026-07-20 14:59:08'),
(510,'COA-2019-047','Chainsaw (Rescue Type)',10,1,'2019-08-13',11088.49,13,'Danilo Del Rosario',1,'Municipal Social Welfare and Development Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-15 09:00:00','2026-07-17 18:12:48'),
(511,'COA-2021-047','CCTV DVR/NVR Unit',7,1,'2021-07-28',38511.70,7,'Alfredo Gonzales',1,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-31 09:00:00','2026-07-20 14:59:08'),
(512,'COA-2022-052','24-Port Network Switch',2,1,'2022-08-21',28322.46,4,'Ricardo Salazar',NULL,'Human Resource Management Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-24 09:00:00','2026-07-20 14:59:08'),
(513,'COA-2018-050','Sprayer (Backpack, Motorized)',9,2,'2018-03-30',47848.24,11,'Imelda Gonzales',2,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-01 09:00:00','2026-07-17 18:12:48'),
(514,'COA-2023-058','Autoclave Sterilizer',8,1,'2023-02-25',112254.36,9,'Maria Rivera',1,'Civil Registrar\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-25 09:00:00','2026-07-17 18:12:48'),
(515,'COA-2023-059','Road Roller',6,1,'2023-02-09',2761005.90,3,'Luz Fernandez',1,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-09 09:00:00','2026-07-17 18:12:48'),
(516,'COA-2021-048','Motorcycle (Service Unit)',5,1,'2021-06-11',2184762.94,15,'Romeo Reyes',1,'General Services Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-13 09:00:00','2026-07-17 18:12:48'),
(517,'COA-2024-048','Electric Fan (Stand Type)',1,1,'2024-10-09',5404.68,16,NULL,NULL,'Information and Communications Technology Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-12 09:00:00','2026-07-20 14:59:08'),
(518,'COA-2025-039','Laser Printer (Monochrome)',2,1,'2025-06-01',25411.21,13,'Ricardo Bautista',1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2025-06-01 09:00:00','2026-07-17 18:12:48'),
(519,'COA-2025-040','Grass Cutter (Riding Type)',6,1,'2025-05-02',2451123.61,11,'Norma Flores',1,'Municipal Planning and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-02 09:00:00','2026-07-17 18:12:48'),
(520,'COA-2021-049','Electric Kettle',1,1,'2021-12-25',39229.93,16,'Cecilia Aguilar',1,'Information and Communications Technology Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-28 09:00:00','2026-07-20 14:59:08'),
(521,'COA-2023-060','Motorcycle (Service Unit)',5,1,'2023-03-28',510916.51,1,'Divina Reyes',NULL,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-30 09:00:00','2026-07-17 18:12:48'),
(522,'COA-2025-041','Sprayer (Backpack, Motorized)',9,2,'2025-08-13',4888.37,8,NULL,NULL,'Assessor\'s Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-15 09:00:00','2026-07-20 14:59:08'),
(523,'COA-2025-042','Autoclave Sterilizer',8,1,'2025-11-11',95034.11,11,'Jose Salazar',NULL,'Municipal Planning and Development Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-13 09:00:00','2026-07-20 14:59:08'),
(524,'COA-2021-050','Steel Filing Cabinet (4-Drawer)',3,1,'2021-09-04',12479.33,9,'Cecilia Ocampo',1,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-04 09:00:00','2026-07-20 14:59:08'),
(525,'COA-2020-032','Visitor\'s Chair (Stackable)',3,1,'2020-06-29',9607.74,1,'Rosa Flores',1,'Office of the Mayor - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-06-29 09:00:00','2026-07-20 14:59:08'),
(526,'COA-2021-051','Concrete Mixer',6,1,'2021-05-13',2445240.51,15,'Imelda Navarro',NULL,'General Services Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-14 09:00:00','2026-07-17 18:12:48'),
(527,'COA-2016-049','Fire Extinguisher (10lbs)',10,1,'2016-03-25',87849.45,8,'Rodrigo Flores',1,'Assessor\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-28 09:00:00','2026-07-17 18:12:48'),
(528,'COA-2016-050','Multi-Purpose Van',5,1,'2016-12-30',747715.05,5,'Juan Marquez',1,'Budget Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-01 09:00:00','2026-07-20 14:59:08'),
(529,'COA-2019-048','Bulletin Board (Cork, Framed)',4,1,'2019-03-25',26688.56,9,'Carlos Cruz',1,'Civil Registrar\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-27 09:00:00','2026-07-17 18:12:48'),
(530,'COA-2018-051','Motorcycle (Service Unit)',5,1,'2018-08-22',1239209.21,9,'Eduardo Del Rosario',NULL,'Civil Registrar\'s Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-08-23 09:00:00','2026-07-17 18:12:48'),
(531,'COA-2023-061','PABX Telephone System',7,1,'2023-12-31',32609.26,7,'Ramon Santos',1,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-02 09:00:00','2026-07-20 14:59:08'),
(532,'COA-2016-051','Life Vest',10,1,'2016-01-22',48922.41,2,'Manuel Del Rosario',1,'Office of the Vice Mayor - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-24 09:00:00','2026-07-20 14:59:08'),
(533,'COA-2017-053','Backhoe Loader',6,1,'2017-06-24',1254354.55,15,'Pedro Ramos',1,'General Services Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-25 09:00:00','2026-07-20 14:59:08'),
(534,'COA-2026-037','IP Desk Phone',7,1,'2026-02-14',28549.59,10,'Ramon Rivera',NULL,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-17 09:00:00','2026-07-17 18:12:48'),
(535,'COA-2018-052','Oxygen Tank with Regulator',8,1,'2018-02-12',7966.21,2,'Josefa Ramos',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-13 09:00:00','2026-07-20 14:59:08'),
(536,'COA-2021-052','Sprayer (Backpack, Motorized)',9,1,'2021-02-17',152790.47,16,NULL,NULL,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-20 09:00:00','2026-07-17 18:12:48'),
(537,'COA-2022-053','Fire Extinguisher (10lbs)',10,1,'2022-07-18',50919.43,7,'Teresa Santos',1,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-21 09:00:00','2026-07-20 14:59:08'),
(538,'COA-2020-033','Document Scanner',2,1,'2020-03-10',79473.58,13,'Antonio Garcia',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-03-13 09:00:00','2026-07-20 14:59:08'),
(539,'COA-2019-049','Service Vehicle (Sedan)',5,1,'2019-09-11',1598302.32,1,NULL,1,'Office of the Mayor - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2019-09-11 09:00:00','2026-07-20 14:59:08'),
(540,'COA-2024-049','Backhoe Loader',6,1,'2024-05-04',1909395.23,2,'Jose Domingo',1,'Office of the Vice Mayor - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-06 09:00:00','2026-07-20 14:59:08'),
(541,'COA-2019-050','CCTV DVR/NVR Unit',7,1,'2019-03-13',34483.74,13,'Ana Villanueva',1,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-15 09:00:00','2026-07-20 14:59:08'),
(542,'COA-2021-053','All-in-One Inkjet Printer',2,1,'2021-09-30',45190.60,12,NULL,1,'Municipal Health Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-10-03 09:00:00','2026-07-20 14:59:08'),
(543,'COA-2016-052','CCTV Camera (Outdoor)',7,1,'2016-06-14',17024.16,3,'Elena Fernandez',1,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2016-06-17 09:00:00','2026-07-17 18:12:48'),
(544,'COA-2017-054','Dump Truck',5,1,'2017-06-07',2030081.33,5,'Ricardo Aguilar',1,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-07 09:00:00','2026-07-20 14:59:08'),
(545,'COA-2019-051','Wheelchair',8,1,'2019-12-26',70889.79,9,'Juan Bautista',NULL,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-26 09:00:00','2026-07-17 18:12:48'),
(546,'COA-2024-050','Metal Detector (Handheld)',10,1,'2024-06-29',43845.16,15,'Antonio Mendoza',1,'General Services Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-29 09:00:00','2026-07-20 14:59:08'),
(547,'COA-2017-055','Electric Fan (Stand Type)',1,1,'2017-04-22',11516.11,13,'Danilo Domingo',1,'Municipal Social Welfare and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-25 09:00:00','2026-07-20 14:59:08'),
(548,'COA-2016-053','Base Radio Station',7,1,'2016-12-24',8242.34,10,'Alfredo Dela Cruz',1,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-24 09:00:00','2026-07-17 18:12:48'),
(549,'COA-2016-054','Water Pump (Irrigation)',9,2,'2016-12-18',29651.24,7,'Ana Mendoza',2,'Treasury Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-19 09:00:00','2026-07-17 18:12:48'),
(550,'COA-2016-055','Life Vest',10,1,'2016-07-27',2732.31,13,'Danilo Aguilar',1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-30 09:00:00','2026-07-17 18:12:48'),
(551,'COA-2022-054','Thermal Scanner',8,1,'2022-08-17',28980.84,17,'Juan Aguilar',NULL,'Disaster Risk Reduction and Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-20 09:00:00','2026-07-20 14:59:08'),
(552,'COA-2021-054','Metal Detector (Handheld)',10,1,'2021-01-10',42569.39,12,'Norma Torres',1,'Municipal Health Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-11 09:00:00','2026-07-17 18:12:48'),
(553,'COA-2025-043','Wheelchair',8,1,'2025-11-26',87174.91,5,'Teresa Del Rosario',1,'Budget Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-28 09:00:00','2026-07-20 14:59:08'),
(554,'COA-2017-056','Stretcher (Foldable)',8,1,'2017-12-10',20023.22,5,'Divina Aguilar',1,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-13 09:00:00','2026-07-20 14:59:08'),
(555,'COA-2025-044','Hand Tractor',9,1,'2025-01-17',79504.51,2,'Ana Gonzales',NULL,'Office of the Vice Mayor - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-20 09:00:00','2026-07-20 14:59:08'),
(556,'COA-2022-055','Steel Filing Cabinet (4-Drawer)',3,1,'2022-10-11',26033.74,17,'Francisco Bautista',NULL,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2022-10-13 09:00:00','2026-07-20 14:59:08'),
(557,'COA-2025-045','Visitor\'s Chair (Stackable)',3,1,'2025-10-07',5408.47,4,'Francisco Rivera',1,'Human Resource Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-10 09:00:00','2026-07-17 18:12:48'),
(558,'COA-2024-051','Digital Blood Pressure Monitor',8,1,'2024-08-16',30569.95,14,'Antonio Villanueva',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-19 09:00:00','2026-07-17 18:12:48'),
(559,'COA-2024-052','Rice Thresher',9,1,'2024-10-29',145012.17,14,'Teresa Pascual',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-31 09:00:00','2026-07-20 14:59:08'),
(560,'COA-2019-052','24-Port Network Switch',2,1,'2019-10-17',38328.77,3,'Teresa Reyes',1,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-19 09:00:00','2026-07-17 18:12:48'),
(561,'COA-2020-034','Sprayer (Backpack, Motorized)',9,5,'2020-09-13',157680.93,10,'Antonio Aquino',5,'Municipal Engineering Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-14 09:00:00','2026-07-20 14:59:08'),
(562,'COA-2023-062','Water Pump (Irrigation)',9,2,'2023-10-27',140358.16,15,NULL,NULL,'General Services Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-10-30 09:00:00','2026-07-17 18:12:48'),
(563,'COA-2022-056','Conference Table (8-Seater)',3,1,'2022-01-24',3687.56,17,'Ricardo Castillo',1,'Disaster Risk Reduction and Management Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-01-25 09:00:00','2026-07-20 14:59:08'),
(564,'COA-2021-055','Service Vehicle (Sedan)',5,1,'2021-08-31',1730975.79,14,'Ramon Fernandez',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-01 09:00:00','2026-07-17 18:12:48'),
(565,'COA-2018-053','Stretcher (Foldable)',8,1,'2018-08-25',43014.95,11,'Divina Marquez',1,'Municipal Planning and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-25 09:00:00','2026-07-17 18:12:48'),
(566,'COA-2017-057','Road Roller',6,1,'2017-02-05',2378175.20,15,'Jose Santos',1,'General Services Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-05 09:00:00','2026-07-17 18:12:48'),
(567,'COA-2022-057','PABX Telephone System',7,1,'2022-07-21',29549.60,9,NULL,1,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-23 09:00:00','2026-07-17 18:12:48'),
(568,'COA-2017-058','Farm Tool Kit',9,1,'2017-04-28',83883.81,17,'Rosa Gonzales',1,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-01 09:00:00','2026-07-20 14:59:08'),
(569,'COA-2017-059','Refrigerator (2-Door)',1,1,'2017-09-19',22002.04,17,NULL,1,'Disaster Risk Reduction and Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-22 09:00:00','2026-07-20 14:59:08'),
(570,'COA-2018-054','Service Pick-up Truck',5,1,'2018-06-02',1883468.87,10,'Ana Gonzales',1,'Municipal Engineering Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-06-04 09:00:00','2026-07-17 18:12:48'),
(571,'COA-2024-053','Autoclave Sterilizer',8,1,'2024-10-05',57814.46,11,'Corazon Garcia',NULL,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-07 09:00:00','2026-07-17 18:12:48'),
(572,'COA-2020-035','Rescue Rope Kit',10,1,'2020-05-05',85722.73,14,'Maria Del Rosario',1,'Municipal Agriculture Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-05 09:00:00','2026-07-20 14:59:08'),
(573,'COA-2023-063','Motorcycle (Service Unit)',5,1,'2023-03-22',599016.05,4,NULL,1,'Human Resource Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-23 09:00:00','2026-07-17 18:12:48'),
(574,'COA-2016-056','Wireless Router',2,1,'2016-03-18',68367.05,6,'Danilo Navarro',1,'Accounting Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-03-20 09:00:00','2026-07-17 18:12:48'),
(575,'COA-2019-053','Autoclave Sterilizer',8,1,'2019-10-24',22890.20,1,'Ricardo Castillo',1,'Office of the Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-26 09:00:00','2026-07-20 14:59:08'),
(576,'COA-2019-054','LCD/LED Monitor 24\"',2,1,'2019-06-10',59931.47,5,'Antonio Mendoza',NULL,'Budget Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-12 09:00:00','2026-07-20 14:59:08'),
(577,'COA-2018-055','All-in-One Inkjet Printer',2,1,'2018-04-09',65666.43,2,'Josefa Rivera',1,'Office of the Vice Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-11 09:00:00','2026-07-20 14:59:08'),
(578,'COA-2026-038','Handheld Two-Way Radio',7,1,'2026-03-31',13939.29,8,NULL,1,'Assessor\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2026-04-03 09:00:00','2026-07-17 18:12:48'),
(579,'COA-2022-058','Swivel Office Chair',3,1,'2022-01-22',15605.95,12,'Gloria Gonzales',1,'Municipal Health Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-01-25 09:00:00','2026-07-20 14:59:08'),
(580,'COA-2016-057','Partition Divider Panel',3,1,'2016-09-03',17222.86,1,'Manuel Aquino',1,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-03 09:00:00','2026-07-20 14:59:08'),
(581,'COA-2025-046','Base Radio Station',7,1,'2025-04-24',33315.64,4,NULL,1,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-27 09:00:00','2026-07-20 14:59:08'),
(582,'COA-2018-056','Nebulizer Machine',8,1,'2018-10-04',41983.13,9,'Corazon Castillo',1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-10-04 09:00:00','2026-07-20 14:59:08'),
(583,'COA-2024-054','PABX Telephone System',7,1,'2024-07-20',25370.59,16,'Rodrigo Fernandez',1,'Information and Communications Technology Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-23 09:00:00','2026-07-20 14:59:08'),
(584,'COA-2020-036','Base Radio Station',7,1,'2020-05-03',38163.70,12,'Juan Bautista',NULL,'Municipal Health Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-06 09:00:00','2026-07-20 14:59:08'),
(585,'COA-2017-060','Concrete Mixer',6,1,'2017-01-03',2098311.72,7,'Danilo Flores',NULL,'Treasury Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-03 09:00:00','2026-07-20 14:59:08'),
(586,'COA-2025-047','Vacuum Cleaner',1,1,'2025-03-17',8324.69,7,'Ricardo Salazar',1,'Treasury Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2025-03-19 09:00:00','2026-07-17 18:12:48'),
(587,'COA-2018-057','Document Scanner',2,1,'2018-11-29',73727.36,5,NULL,1,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-01 09:00:00','2026-07-20 14:59:08'),
(588,'COA-2016-058','Sprayer (Backpack, Motorized)',9,1,'2016-01-09',154206.26,15,'Leonora Aguilar',1,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-11 09:00:00','2026-07-17 18:12:48'),
(589,'COA-2026-039','Vacuum Cleaner',1,1,'2026-04-19',30451.54,9,'Manuel Torres',NULL,'Civil Registrar\'s Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2026-04-20 09:00:00','2026-07-17 18:12:48'),
(590,'COA-2026-040','Base Radio Station',7,1,'2026-04-14',10867.26,3,'Jose Fernandez',NULL,'Sangguniang Bayan Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2026-04-14 09:00:00','2026-07-17 18:12:48'),
(591,'COA-2018-058','Backhoe Loader',6,1,'2018-10-09',1699693.10,9,NULL,NULL,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-09 09:00:00','2026-07-17 18:12:48'),
(592,'COA-2016-059','Fire Extinguisher (10lbs)',10,1,'2016-12-16',87254.44,4,'Romeo Marquez',1,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-16 09:00:00','2026-07-20 14:59:08'),
(593,'COA-2023-064','Desktop Computer Set (Core i5)',2,1,'2023-08-07',50622.13,4,'Manuel Domingo',1,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-10 09:00:00','2026-07-20 14:59:08'),
(594,'COA-2019-055','CCTV DVR/NVR Unit',7,1,'2019-10-23',42347.36,4,'Francisco Rivera',1,'Human Resource Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-24 09:00:00','2026-07-20 14:59:08'),
(595,'COA-2023-065','Chainsaw (Rescue Type)',10,1,'2023-02-23',25834.61,5,'Norma Cruz',1,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-23 09:00:00','2026-07-20 14:59:08'),
(596,'COA-2022-059','Grass Cutter (Riding Type)',6,1,'2022-07-18',2560162.64,10,'Luz Cruz',1,'Municipal Engineering Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-20 09:00:00','2026-07-20 14:59:08'),
(597,'COA-2020-037','Water Pump (Irrigation)',9,1,'2020-09-24',175854.15,2,'Carlos Santos',1,'Office of the Vice Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-24 09:00:00','2026-07-17 18:12:48'),
(598,'COA-2022-060','Life Vest',10,1,'2022-11-28',40938.66,11,'Francisco Reyes',1,'Municipal Planning and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-29 09:00:00','2026-07-17 18:12:48'),
(599,'COA-2018-059','Water Tanker Truck',6,1,'2018-04-20',875096.86,13,NULL,1,'Municipal Social Welfare and Development Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-04-23 09:00:00','2026-07-17 18:12:48'),
(600,'COA-2023-066','Nebulizer Machine',8,1,'2023-01-29',6702.72,7,'Carlos Villanueva',1,'Treasury Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-30 09:00:00','2026-07-17 18:12:48'),
(601,'COA-2026-041','Steel Filing Cabinet (4-Drawer)',3,1,'2026-03-19',23482.75,9,'Rodrigo Bautista',1,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-21 09:00:00','2026-07-17 18:12:48'),
(602,'COA-2025-048','Metal Detector (Handheld)',10,1,'2025-11-06',8080.11,14,'Gloria Garcia',NULL,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-07 09:00:00','2026-07-17 18:12:48'),
(603,'COA-2025-049','Microwave Oven',1,1,'2025-07-31',43953.36,7,'Maria Fernandez',1,'Treasury Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2025-07-31 09:00:00','2026-07-17 18:12:48'),
(604,'COA-2017-061','Chainsaw (Rescue Type)',10,1,'2017-11-16',38094.77,3,NULL,1,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-17 09:00:00','2026-07-17 18:12:48'),
(605,'COA-2019-056','Autoclave Sterilizer',8,1,'2019-01-04',77115.51,16,'Rodrigo Reyes',1,'Information and Communications Technology Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-06 09:00:00','2026-07-20 14:59:08'),
(606,'COA-2025-050','IP Desk Phone',7,1,'2025-06-12',13317.49,6,'Ernesto Santos',1,'Accounting Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-06-15 09:00:00','2026-07-17 18:12:48'),
(607,'COA-2020-038','Nebulizer Machine',8,1,'2020-08-02',96833.78,14,'Manuel Dela Cruz',1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-05 09:00:00','2026-07-20 14:59:08'),
(608,'COA-2024-055','Water Pump (Irrigation)',9,1,'2024-10-23',20869.21,3,'Maria Gonzales',NULL,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-24 09:00:00','2026-07-17 18:12:48'),
(609,'COA-2025-051','Binding Machine',4,1,'2025-08-03',3529.10,5,'Alfredo Aquino',NULL,'Budget Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-05 09:00:00','2026-07-20 14:59:08'),
(610,'COA-2018-060','Bulletin Board (Cork, Framed)',4,1,'2018-08-15',47795.64,16,'Divina Santos',1,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-15 09:00:00','2026-07-20 14:59:08'),
(611,'COA-2017-062','Water Dispenser (Hot & Cold)',1,1,'2017-07-23',18542.53,12,'Josefa Del Rosario',NULL,'Municipal Health Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-25 09:00:00','2026-07-17 18:12:48'),
(612,'COA-2022-061','Concrete Mixer',6,1,'2022-05-13',441795.63,1,'Antonio Navarro',NULL,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2022-05-15 09:00:00','2026-07-17 18:12:48'),
(613,'COA-2017-063','Laminating Machine',4,1,'2017-03-20',38309.93,16,'Romeo Villanueva',1,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2017-03-22 09:00:00','2026-07-17 18:12:48'),
(614,'COA-2019-057','All-in-One Inkjet Printer',2,1,'2019-03-08',25177.08,13,'Jose Pascual',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-09 09:00:00','2026-07-17 18:12:48'),
(615,'COA-2021-056','Steel Filing Cabinet (4-Drawer)',3,2,'2021-05-12',26796.59,14,NULL,2,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-14 09:00:00','2026-07-20 14:59:08'),
(616,'COA-2021-057','Dump Truck',5,1,'2021-08-20',1648462.88,7,'Juan Garcia',1,'Treasury Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-08-20 09:00:00','2026-07-17 18:12:48'),
(617,'COA-2021-058','Inflatable Rescue Boat',10,1,'2021-02-27',55580.35,16,'Luz Fernandez',NULL,'Information and Communications Technology Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-02 09:00:00','2026-07-20 14:59:08'),
(618,'COA-2018-061','CCTV Camera (Outdoor)',7,1,'2018-01-05',33662.87,8,'Gloria Del Rosario',1,'Assessor\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-08 09:00:00','2026-07-17 18:12:48'),
(619,'COA-2023-067','Dump Truck',5,1,'2023-10-30',1714216.43,3,'Josefa Aguilar',NULL,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-01 09:00:00','2026-07-17 18:12:48'),
(620,'COA-2018-062','Executive Office Desk',3,2,'2018-04-29',1916.04,9,'Imelda Ocampo',2,'Civil Registrar\'s Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-01 09:00:00','2026-07-20 14:59:08'),
(621,'COA-2023-068','Partition Divider Panel',3,2,'2023-07-08',13564.37,11,'Imelda Flores',NULL,'Municipal Planning and Development Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-11 09:00:00','2026-07-20 14:59:08'),
(622,'COA-2017-064','Steel Locker Cabinet',3,1,'2017-05-23',3279.29,10,'Imelda Ramos',1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-25 09:00:00','2026-07-17 18:12:48'),
(623,'COA-2023-069','Refrigerator (2-Door)',1,1,'2023-03-10',23007.47,17,'Maria Cruz',1,'Disaster Risk Reduction and Management Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-03-11 09:00:00','2026-07-17 18:12:48'),
(624,'COA-2017-065','Photocopier Machine (Multi-function)',4,1,'2017-01-09',29144.33,7,NULL,1,'Treasury Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-12 09:00:00','2026-07-20 14:59:08'),
(625,'COA-2016-060','Steel Locker Cabinet',3,5,'2016-06-29',4085.93,6,'Cecilia Fernandez',5,'Accounting Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-01 09:00:00','2026-07-20 14:59:08'),
(626,'COA-2016-061','Water Tanker Truck',6,1,'2016-03-02',2213879.36,6,'Carlos Pascual',1,'Accounting Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-03-03 09:00:00','2026-07-20 14:59:08'),
(627,'COA-2020-039','Wireless Router',2,1,'2020-08-10',66868.52,7,'Ana Marquez',1,'Treasury Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-12 09:00:00','2026-07-20 14:59:08'),
(628,'COA-2019-058','Base Radio Station',7,1,'2019-09-22',29502.52,5,NULL,1,'Budget Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-23 09:00:00','2026-07-20 14:59:08'),
(629,'COA-2022-062','Photocopier Machine (Multi-function)',4,1,'2022-08-03',17421.57,17,'Romeo Bautista',1,'Disaster Risk Reduction and Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-06 09:00:00','2026-07-17 18:12:48'),
(630,'COA-2018-063','Executive Office Desk',3,1,'2018-04-17',25947.36,13,'Francisco Ocampo',1,'Municipal Social Welfare and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-19 09:00:00','2026-07-17 18:12:48'),
(631,'COA-2025-052','Electric Kettle',1,1,'2025-07-01',20493.24,8,'Maria Del Rosario',1,'Assessor\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-02 09:00:00','2026-07-17 18:12:48'),
(632,'COA-2025-053','Water Cooler/Dispenser',1,1,'2025-10-02',6174.21,3,'Rodrigo Garcia',1,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-03 09:00:00','2026-07-17 18:12:48'),
(633,'COA-2019-059','Base Radio Station',7,1,'2019-06-29',33171.14,15,'Rosa Cruz',NULL,'General Services Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-30 09:00:00','2026-07-20 14:59:08'),
(634,'COA-2020-040','Road Roller',6,1,'2020-03-27',1691533.43,13,'Corazon Ocampo',1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2020-03-27 09:00:00','2026-07-20 14:59:08'),
(635,'COA-2022-063','Metal Detector (Handheld)',10,1,'2022-03-14',18340.04,5,'Luz Pascual',1,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-15 09:00:00','2026-07-20 14:59:08'),
(636,'COA-2016-062','Laminating Machine',4,1,'2016-02-22',33470.13,1,NULL,1,'Office of the Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-23 09:00:00','2026-07-17 18:12:48'),
(637,'COA-2020-041','Water Dispenser (Hot & Cold)',1,1,'2020-04-25',12696.98,4,'Ramon Ocampo',1,'Human Resource Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-25 09:00:00','2026-07-17 18:12:48'),
(638,'COA-2021-059','Photocopier Machine (Multi-function)',4,1,'2021-05-10',60131.05,8,'Danilo Del Rosario',1,'Assessor\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-12 09:00:00','2026-07-17 18:12:48'),
(639,'COA-2016-063','Fire Extinguisher (10lbs)',10,1,'2016-02-20',73700.41,6,'Gloria Domingo',NULL,'Accounting Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-20 09:00:00','2026-07-20 14:59:08'),
(640,'COA-2023-070','IP Desk Phone',7,1,'2023-10-04',23777.49,9,'Romeo Domingo',1,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-04 09:00:00','2026-07-20 14:59:08'),
(641,'COA-2019-060','Generator Set (25 kVA)',6,1,'2019-01-06',947147.83,5,'Danilo Villanueva',1,'Budget Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-09 09:00:00','2026-07-20 14:59:08'),
(642,'COA-2017-066','IP Desk Phone',7,1,'2017-12-23',10422.00,6,'Josefa Mendoza',1,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-25 09:00:00','2026-07-20 14:59:08'),
(643,'COA-2026-042','Fax Machine',4,1,'2026-02-12',30325.29,9,NULL,1,'Civil Registrar\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-15 09:00:00','2026-07-17 18:12:48'),
(644,'COA-2021-060','Inflatable Rescue Boat',10,1,'2021-05-11',64570.83,8,'Maria Ramos',NULL,'Assessor\'s Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-11 09:00:00','2026-07-20 14:59:08'),
(645,'COA-2021-061','Sprayer (Backpack, Motorized)',9,1,'2021-06-13',110171.58,9,'Imelda Castillo',1,'Civil Registrar\'s Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-16 09:00:00','2026-07-20 14:59:08'),
(646,'COA-2016-064','Water Tanker Truck',6,1,'2016-01-13',2831043.31,4,'Alfredo Garcia',NULL,'Human Resource Management Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-14 09:00:00','2026-07-20 14:59:08'),
(647,'COA-2021-062','Inflatable Rescue Boat',10,1,'2021-10-10',63401.24,16,'Rodrigo Castillo',1,'Information and Communications Technology Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-10-13 09:00:00','2026-07-17 18:12:48'),
(648,'COA-2024-056','Weighing Scale (Digital)',8,1,'2024-04-15',42777.57,13,NULL,1,'Municipal Social Welfare and Development Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-17 09:00:00','2026-07-20 14:59:08'),
(649,'COA-2025-054','Executive Office Desk',3,1,'2025-10-29',14544.39,17,'Alfredo Del Rosario',1,'Disaster Risk Reduction and Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-30 09:00:00','2026-07-20 14:59:08'),
(650,'COA-2017-067','Paper Shredder (Heavy Duty)',4,1,'2017-11-29',9539.12,7,NULL,1,'Treasury Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-29 09:00:00','2026-07-20 14:59:08'),
(651,'COA-2023-071','Oxygen Tank with Regulator',8,1,'2023-06-18',110844.24,4,'Josefa Santos',1,'Human Resource Management Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-18 09:00:00','2026-07-20 14:59:08'),
(652,'COA-2025-055','Base Radio Station',7,1,'2025-01-24',12000.91,14,'Jose Bautista',1,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-26 09:00:00','2026-07-17 18:12:48'),
(653,'COA-2022-064','Generator Set (25 kVA)',6,1,'2022-06-21',354783.70,13,'Cecilia Torres',NULL,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-24 09:00:00','2026-07-17 18:12:48'),
(654,'COA-2017-068','Inflatable Rescue Boat',10,1,'2017-03-12',2854.53,8,NULL,1,'Assessor\'s Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-15 09:00:00','2026-07-20 14:59:08'),
(655,'COA-2024-057','Dump Truck',5,1,'2024-05-17',1935973.07,5,'Maria Cruz',NULL,'Budget Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-17 09:00:00','2026-07-20 14:59:08'),
(656,'COA-2019-061','Fax Machine',4,1,'2019-04-08',6646.38,16,'Pedro Marquez',NULL,'Information and Communications Technology Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-11 09:00:00','2026-07-20 14:59:08'),
(657,'COA-2019-062','Oxygen Tank with Regulator',8,1,'2019-05-10',118940.99,13,'Antonio Aguilar',1,'Municipal Social Welfare and Development Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-13 09:00:00','2026-07-20 14:59:08'),
(658,'COA-2017-069','Typewriter (Manual)',4,1,'2017-02-02',23051.95,13,'Leonora Reyes',1,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-03 09:00:00','2026-07-20 14:59:08'),
(659,'COA-2024-058','Photocopier Machine (Multi-function)',4,1,'2024-03-30',25458.00,7,NULL,1,'Treasury Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-02 09:00:00','2026-07-20 14:59:08'),
(660,'COA-2019-063','Water Cooler/Dispenser',1,1,'2019-12-27',11930.73,4,'Ricardo Fernandez',1,'Human Resource Management Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-28 09:00:00','2026-07-20 14:59:08'),
(661,'COA-2023-072','Oxygen Tank with Regulator',8,1,'2023-09-18',78856.44,10,'Danilo Del Rosario',1,'Municipal Engineering Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-20 09:00:00','2026-07-20 14:59:08'),
(662,'COA-2016-065','Laptop Computer (Business Series)',2,1,'2016-12-04',45159.04,4,'Ricardo Flores',1,'Human Resource Management Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-04 09:00:00','2026-07-20 14:59:08'),
(663,'COA-2023-073','CCTV DVR/NVR Unit',7,1,'2023-03-25',20930.40,16,'Ana Castillo',NULL,'Information and Communications Technology Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-25 09:00:00','2026-07-20 14:59:08'),
(664,'COA-2021-063','Hand Tractor',9,5,'2021-06-24',151255.91,17,'Alfredo Fernandez',NULL,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-25 09:00:00','2026-07-17 18:12:48'),
(665,'COA-2024-059','Electric Kettle',1,1,'2024-12-22',8959.88,15,'Carlos Fernandez',1,'General Services Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-12-23 09:00:00','2026-07-17 18:12:48'),
(666,'COA-2019-064','24-Port Network Switch',2,1,'2019-05-07',82369.54,17,'Imelda Dela Cruz',1,'Disaster Risk Reduction and Management Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-07 09:00:00','2026-07-20 14:59:08'),
(667,'COA-2023-074','Life Vest',10,1,'2023-10-18',50607.96,16,NULL,1,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2023-10-20 09:00:00','2026-07-17 18:12:48'),
(668,'COA-2017-070','Motorcycle (Service Unit)',5,1,'2017-07-03',1416123.60,7,'Ramon Garcia',1,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-06 09:00:00','2026-07-17 18:12:48'),
(669,'COA-2023-075','Service Pick-up Truck',5,1,'2023-10-15',1387832.56,14,'Norma Ramos',1,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-16 09:00:00','2026-07-17 18:12:48'),
(670,'COA-2020-042','Backhoe Loader',6,1,'2020-04-01',3097450.45,14,'Ramon Bautista',1,'Municipal Agriculture Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-02 09:00:00','2026-07-20 14:59:08'),
(671,'COA-2025-056','Patrol Motorcycle',5,1,'2025-09-28',845089.57,5,'Manuel Flores',NULL,'Budget Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-28 09:00:00','2026-07-20 14:59:08'),
(672,'COA-2021-064','Nebulizer Machine',8,1,'2021-12-06',84503.98,4,NULL,NULL,'Human Resource Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-08 09:00:00','2026-07-20 14:59:08'),
(673,'COA-2021-065','Seedling Tray Set',9,1,'2021-05-07',49224.27,13,'Danilo Garcia',1,'Municipal Social Welfare and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-07 09:00:00','2026-07-17 18:12:48'),
(674,'COA-2023-076','Bulletin Board (Cork, Framed)',4,1,'2023-12-04',14352.48,14,NULL,NULL,'Municipal Agriculture Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-07 09:00:00','2026-07-17 18:12:48'),
(675,'COA-2019-065','Ambulance Unit',5,1,'2019-06-05',1798512.20,3,'Rodrigo Santos',1,'Sangguniang Bayan Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-07 09:00:00','2026-07-20 14:59:08'),
(676,'COA-2023-077','Water Dispenser (Hot & Cold)',1,1,'2023-08-05',27681.94,14,'Imelda Gonzales',NULL,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-05 09:00:00','2026-07-20 14:59:08'),
(677,'COA-2024-060','Generator Set (25 kVA)',6,1,'2024-04-14',3059974.91,8,'Romeo Rivera',NULL,'Assessor\'s Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-04-17 09:00:00','2026-07-17 18:12:48'),
(678,'COA-2017-071','Hand Tractor',9,1,'2017-12-17',151655.68,8,'Maria Aguilar',1,'Assessor\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-20 09:00:00','2026-07-20 14:59:08'),
(679,'COA-2019-066','External Hard Drive 2TB',2,1,'2019-05-10',29896.51,10,'Norma Fernandez',1,'Municipal Engineering Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-10 09:00:00','2026-07-17 18:12:48'),
(680,'COA-2016-066','Nebulizer Machine',8,1,'2016-08-23',2198.10,16,'Luz Aquino',1,'Information and Communications Technology Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-08-25 09:00:00','2026-07-20 14:59:08'),
(681,'COA-2021-066','All-in-One Inkjet Printer',2,1,'2021-07-08',13610.01,14,'Pedro Aguilar',1,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-10 09:00:00','2026-07-17 18:12:48'),
(682,'COA-2026-043','Road Roller',6,1,'2026-01-02',1878818.05,14,'Francisco Del Rosario',NULL,'Municipal Agriculture Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-04 09:00:00','2026-07-17 18:12:48'),
(683,'COA-2016-067','Typewriter (Manual)',4,1,'2016-06-13',27461.85,10,'Romeo Reyes',1,'Municipal Engineering Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-15 09:00:00','2026-07-20 14:59:08'),
(684,'COA-2019-067','Autoclave Sterilizer',8,1,'2019-08-23',60970.24,5,NULL,1,'Budget Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2019-08-24 09:00:00','2026-07-20 14:59:08'),
(685,'COA-2020-043','Electric Fan (Stand Type)',1,1,'2020-10-25',25302.25,11,'Josefa Santos',NULL,'Municipal Planning and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-26 09:00:00','2026-07-17 18:12:48'),
(686,'COA-2018-064','Bulletin Board (Cork, Framed)',4,1,'2018-03-23',46800.58,14,'Danilo Ocampo',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-26 09:00:00','2026-07-20 14:59:08'),
(687,'COA-2018-065','Water Dispenser (Hot & Cold)',1,1,'2018-02-26',24880.91,9,'Jose Reyes',1,'Civil Registrar\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-28 09:00:00','2026-07-17 18:12:48'),
(688,'COA-2023-078','Hand Tractor',9,1,'2023-03-22',22924.70,14,'Carmen Marquez',1,'Municipal Agriculture Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-24 09:00:00','2026-07-20 14:59:08'),
(689,'COA-2020-044','Rescue Rope Kit',10,1,'2020-10-30',25460.46,4,'Antonio Villanueva',NULL,'Human Resource Management Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-30 09:00:00','2026-07-20 14:59:08'),
(690,'COA-2022-065','Life Vest',10,1,'2022-10-12',24157.46,17,'Eduardo Domingo',1,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-12 09:00:00','2026-07-17 18:12:48'),
(691,'COA-2023-079','Bulletin Board (Cork, Framed)',4,1,'2023-11-26',60381.04,7,'Cecilia Cruz',1,'Treasury Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-26 09:00:00','2026-07-17 18:12:48'),
(692,'COA-2025-057','Megaphone (Bullhorn)',7,1,'2025-12-30',38771.13,9,NULL,1,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-30 09:00:00','2026-07-17 18:12:48'),
(693,'COA-2017-072','Seedling Tray Set',9,1,'2017-11-14',126468.65,1,'Maria Navarro',1,'Office of the Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-15 09:00:00','2026-07-17 18:12:48'),
(694,'COA-2020-045','UPS (Uninterruptible Power Supply)',2,1,'2020-11-28',36963.73,6,'Manuel Cruz',1,'Accounting Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-28 09:00:00','2026-07-17 18:12:48'),
(695,'COA-2021-067','Farm Tool Kit',9,5,'2021-08-25',49184.31,15,NULL,5,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-28 09:00:00','2026-07-17 18:12:48'),
(696,'COA-2019-068','Patrol Motorcycle',5,1,'2019-01-12',1833587.31,5,'Elena Torres',NULL,'Budget Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-15 09:00:00','2026-07-20 12:47:01'),
(697,'COA-2020-046','Motorcycle (Service Unit)',5,1,'2020-07-30',966066.84,5,NULL,NULL,'Budget Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-02 09:00:00','2026-07-20 14:59:08'),
(698,'COA-2024-061','Metal Detector (Handheld)',10,1,'2024-02-07',65994.73,4,NULL,1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-07 09:00:00','2026-07-17 18:12:48'),
(699,'COA-2017-073','Inflatable Rescue Boat',10,1,'2017-09-29',23550.25,13,'Carmen Garcia',1,'Municipal Social Welfare and Development Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-01 09:00:00','2026-07-20 14:59:08'),
(700,'COA-2016-068','Conference Table (8-Seater)',3,1,'2016-03-27',24924.78,10,'Imelda Cruz',NULL,'Municipal Engineering Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-03-27 09:00:00','2026-07-17 18:12:48'),
(701,'COA-2024-062','CCTV Camera (Outdoor)',7,1,'2024-02-14',8334.88,4,'Juan Cruz',1,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-17 09:00:00','2026-07-20 14:59:08'),
(702,'COA-2023-080','Motorcycle (Service Unit)',5,1,'2023-01-13',473619.58,5,NULL,1,'Budget Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-14 09:00:00','2026-07-20 14:59:08'),
(703,'COA-2025-058','Rescue Rope Kit',10,1,'2025-02-22',30586.80,15,'Elena Reyes',1,'General Services Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-02-23 09:00:00','2026-07-20 14:59:08'),
(704,'COA-2017-074','Hand Tractor',9,1,'2017-08-03',7736.15,14,'Pedro Aquino',NULL,'Municipal Agriculture Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-04 09:00:00','2026-07-20 14:59:08'),
(705,'COA-2018-066','Steel Filing Cabinet (4-Drawer)',3,1,'2018-07-08',10775.85,4,'Ana Aquino',1,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-08 09:00:00','2026-07-17 18:12:48'),
(706,'COA-2023-081','Conference Table (8-Seater)',3,1,'2023-01-03',24660.78,10,'Josefa Del Rosario',NULL,'Municipal Engineering Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-05 09:00:00','2026-07-20 14:59:08'),
(707,'COA-2017-075','Steel Locker Cabinet',3,2,'2017-08-28',20532.00,11,'Josefa Santos',NULL,'Municipal Planning and Development Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-28 09:00:00','2026-07-20 14:59:08'),
(708,'COA-2019-069','PABX Telephone System',7,1,'2019-07-31',20512.86,12,'Teresa Cruz',1,'Municipal Health Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-03 09:00:00','2026-07-20 14:59:08'),
(709,'COA-2020-047','Weighing Scale (Digital)',8,1,'2020-04-24',70344.23,8,'Eduardo Marquez',1,'Assessor\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-26 09:00:00','2026-07-20 14:59:08'),
(710,'COA-2016-069','Bookshelf (Wooden, 5-Tier)',3,1,'2016-09-01',23946.54,4,NULL,1,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-01 09:00:00','2026-07-20 14:59:08'),
(711,'COA-2017-076','Water Dispenser (Hot & Cold)',1,1,'2017-04-25',22316.69,5,'Teresa Aquino',NULL,'Budget Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2017-04-28 09:00:00','2026-07-20 14:59:08'),
(712,'COA-2018-067','Steel Filing Cabinet (4-Drawer)',3,1,'2018-09-30',16454.11,3,'Pedro Mendoza',1,'Sangguniang Bayan Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-03 09:00:00','2026-07-20 14:59:08'),
(713,'COA-2017-077','Water Dispenser (Hot & Cold)',1,1,'2017-03-31',5650.04,10,'Corazon Mendoza',1,'Municipal Engineering Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-01 09:00:00','2026-07-17 18:12:48'),
(714,'COA-2019-070','Dump Truck',5,1,'2019-06-07',847801.00,17,NULL,1,'Disaster Risk Reduction and Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-10 09:00:00','2026-07-20 14:59:08'),
(715,'COA-2018-068','Paper Shredder (Heavy Duty)',4,1,'2018-01-22',53626.65,13,'Antonio Fernandez',1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-22 09:00:00','2026-07-20 14:59:08'),
(716,'COA-2022-066','24-Port Network Switch',2,1,'2022-10-06',9187.81,12,'Cecilia Bautista',1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-08 09:00:00','2026-07-20 14:59:08'),
(717,'COA-2019-071','Refrigerator (2-Door)',1,1,'2019-01-07',53774.82,8,'Eduardo Salazar',NULL,'Assessor\'s Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-01-10 09:00:00','2026-07-17 18:12:48'),
(718,'COA-2021-068','Service Pick-up Truck',5,1,'2021-08-10',1000326.77,13,'Carmen Garcia',NULL,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2021-08-12 09:00:00','2026-07-20 14:59:08'),
(719,'COA-2019-072','Oxygen Tank with Regulator',8,1,'2019-04-03',19457.23,2,'Romeo Fernandez',1,'Office of the Vice Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-04 09:00:00','2026-07-17 18:12:48'),
(720,'COA-2024-063','Seedling Tray Set',9,5,'2024-03-03',167685.10,17,'Divina Garcia',5,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-03 09:00:00','2026-07-20 14:59:08'),
(721,'COA-2017-078','Chainsaw (Rescue Type)',10,1,'2017-09-16',60384.44,3,'Divina Dela Cruz',1,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-18 09:00:00','2026-07-20 14:59:08'),
(722,'COA-2017-079','Steel Filing Cabinet (4-Drawer)',3,1,'2017-10-23',16650.51,10,'Jose Mendoza',1,'Municipal Engineering Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-24 09:00:00','2026-07-17 18:12:48'),
(723,'COA-2016-070','24-Port Network Switch',2,1,'2016-06-11',74002.25,16,'Leonora Cruz',1,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-13 09:00:00','2026-07-17 18:12:48'),
(724,'COA-2025-059','Digital Blood Pressure Monitor',8,1,'2025-11-02',75042.73,9,'Norma Flores',1,'Civil Registrar\'s Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-11-03 09:00:00','2026-07-20 14:59:08'),
(725,'COA-2018-069','PABX Telephone System',7,1,'2018-07-02',39651.75,3,'Carmen Pascual',NULL,'Sangguniang Bayan Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-03 09:00:00','2026-07-20 14:59:08'),
(726,'COA-2018-070','PABX Telephone System',7,1,'2018-03-28',16470.63,14,'Corazon Salazar',NULL,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-28 09:00:00','2026-07-17 18:12:48'),
(727,'COA-2022-067','Photocopier Machine (Multi-function)',4,1,'2022-05-16',64244.27,11,'Maria Aquino',1,'Municipal Planning and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-19 09:00:00','2026-07-17 18:12:48'),
(728,'COA-2016-071','Wireless Router',2,1,'2016-10-10',38595.34,5,'Danilo Pascual',1,'Budget Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-10 09:00:00','2026-07-20 12:47:01'),
(729,'COA-2017-080','Road Roller',6,1,'2017-11-04',1345437.34,10,'Josefa Gonzales',NULL,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-06 09:00:00','2026-07-20 14:59:08'),
(730,'COA-2016-072','Metal Detector (Handheld)',10,1,'2016-11-14',64120.51,7,'Antonio Del Rosario',1,'Treasury Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-11-15 09:00:00','2026-07-20 14:59:08'),
(731,'COA-2024-064','Generator Set (25 kVA)',6,1,'2024-11-18',1508201.92,4,'Juan Pascual',1,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-18 09:00:00','2026-07-17 18:12:48'),
(732,'COA-2018-071','Bookshelf (Wooden, 5-Tier)',3,1,'2018-06-04',26723.70,13,NULL,1,'Municipal Social Welfare and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-04 09:00:00','2026-07-17 18:12:48'),
(733,'COA-2023-082','External Hard Drive 2TB',2,1,'2023-04-11',39296.19,16,'Alfredo Gonzales',1,'Information and Communications Technology Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-14 09:00:00','2026-07-20 14:59:08'),
(734,'COA-2022-068','Inflatable Rescue Boat',10,1,'2022-02-01',37485.39,6,'Danilo Del Rosario',1,'Accounting Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2022-02-04 09:00:00','2026-07-20 14:59:08'),
(735,'COA-2022-069','LCD/LED Monitor 24\"',2,1,'2022-11-29',15086.67,1,'Corazon Gonzales',NULL,'Office of the Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-30 09:00:00','2026-07-20 14:59:08'),
(736,'COA-2017-081','Stretcher (Foldable)',8,1,'2017-04-13',102976.60,13,NULL,NULL,'Municipal Social Welfare and Development Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-14 09:00:00','2026-07-20 14:59:08'),
(737,'COA-2024-065','Air Conditioning Unit (1.5HP Split Type)',1,1,'2024-10-08',29146.94,12,'Imelda Ramos',NULL,'Municipal Health Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-09 09:00:00','2026-07-20 14:59:08'),
(738,'COA-2017-082','Electric Kettle',1,1,'2017-09-20',46640.41,1,'Norma Cruz',NULL,'Office of the Mayor - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-23 09:00:00','2026-07-20 14:59:08'),
(739,'COA-2024-066','CCTV Camera (Outdoor)',7,1,'2024-12-26',20736.85,2,NULL,1,'Office of the Vice Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2024-12-28 09:00:00','2026-07-20 14:59:08'),
(740,'COA-2023-083','Seedling Tray Set',9,2,'2023-01-30',152294.92,4,'Ramon Gonzales',2,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-01 09:00:00','2026-07-20 14:59:08'),
(741,'COA-2022-070','Vacuum Cleaner',1,1,'2022-05-31',3827.72,3,'Francisco Fernandez',NULL,'Sangguniang Bayan Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-01 09:00:00','2026-07-17 18:12:48'),
(742,'COA-2023-084','Handheld Two-Way Radio',7,1,'2023-05-24',14186.01,9,NULL,1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-27 09:00:00','2026-07-20 14:59:08'),
(743,'COA-2026-044','Service Pick-up Truck',5,1,'2026-01-12',612360.00,9,'Carmen Torres',1,'Civil Registrar\'s Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-15 09:00:00','2026-07-17 18:12:48'),
(744,'COA-2025-060','Road Roller',6,1,'2025-01-24',862448.34,15,'Rosa Del Rosario',1,'General Services Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-26 09:00:00','2026-07-20 14:59:08'),
(745,'COA-2017-083','Chainsaw (Rescue Type)',10,1,'2017-10-10',70977.81,1,NULL,1,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-11 09:00:00','2026-07-17 18:12:48'),
(746,'COA-2019-073','Typewriter (Manual)',4,1,'2019-09-03',16625.19,1,'Pedro Ramos',1,'Office of the Mayor - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-06 09:00:00','2026-07-20 14:59:08'),
(747,'COA-2021-069','Autoclave Sterilizer',8,1,'2021-09-30',110798.25,14,'Carlos Del Rosario',1,'Municipal Agriculture Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-30 09:00:00','2026-07-17 18:12:48'),
(748,'COA-2025-061','Thermal Scanner',8,1,'2025-11-25',51712.87,14,'Alfredo Castillo',1,'Municipal Agriculture Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-25 09:00:00','2026-07-20 14:59:08'),
(749,'COA-2017-084','Desktop Computer Set (Core i5)',2,1,'2017-11-16',81731.60,15,'Teresa Villanueva',1,'General Services Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-19 09:00:00','2026-07-20 14:59:08'),
(750,'COA-2024-067','Road Roller',6,1,'2024-11-13',1369571.87,14,'Imelda Aquino',NULL,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-16 09:00:00','2026-07-20 14:59:08'),
(751,'COA-2026-045','Rescue Rope Kit',10,1,'2026-01-29',54232.57,11,'Corazon Torres',NULL,'Municipal Planning and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-01 09:00:00','2026-07-17 18:12:48'),
(752,'COA-2023-085','Emergency Light Tower',10,1,'2023-08-26',42474.12,14,'Carlos Torres',1,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-29 09:00:00','2026-07-20 14:59:08'),
(753,'COA-2018-072','Grass Cutter (Riding Type)',6,1,'2018-08-26',410615.79,13,'Divina Navarro',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-27 09:00:00','2026-07-20 14:59:08'),
(754,'COA-2019-074','Farm Tool Kit',9,1,'2019-10-13',15758.65,2,'Divina Aguilar',1,'Office of the Vice Mayor - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-13 09:00:00','2026-07-20 14:59:08'),
(755,'COA-2023-086','PABX Telephone System',7,1,'2023-10-23',23466.81,10,'Gloria Bautista',1,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-23 09:00:00','2026-07-17 18:12:48'),
(756,'COA-2017-085','Handheld Two-Way Radio',7,1,'2017-11-28',10624.29,8,NULL,1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-28 09:00:00','2026-07-20 14:59:08'),
(757,'COA-2016-073','Microwave Oven',1,1,'2016-07-15',6439.71,4,'Corazon Domingo',1,'Human Resource Management Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-15 09:00:00','2026-07-20 14:59:08'),
(758,'COA-2023-087','Inflatable Rescue Boat',10,1,'2023-02-21',64145.88,14,'Elena Navarro',1,'Municipal Agriculture Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-22 09:00:00','2026-07-20 14:59:08'),
(759,'COA-2019-075','Motorcycle (Service Unit)',5,1,'2019-12-16',1912198.67,3,'Rodrigo Ocampo',1,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-16 09:00:00','2026-07-17 18:12:48'),
(760,'COA-2021-070','Handheld Two-Way Radio',7,1,'2021-06-20',16969.13,7,'Ernesto Rivera',1,'Treasury Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-22 09:00:00','2026-07-20 14:59:08'),
(761,'COA-2026-046','Bookshelf (Wooden, 5-Tier)',3,2,'2026-04-12',27331.73,8,NULL,2,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-13 09:00:00','2026-07-20 14:59:08'),
(762,'COA-2017-086','Inflatable Rescue Boat',10,1,'2017-08-26',83486.25,4,'Elena Dela Cruz',1,'Human Resource Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-27 09:00:00','2026-07-17 18:12:48'),
(763,'COA-2020-048','All-in-One Inkjet Printer',2,1,'2020-11-02',18748.36,12,'Ricardo Castillo',NULL,'Municipal Health Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-03 09:00:00','2026-07-20 14:59:08'),
(764,'COA-2017-087','Binding Machine',4,1,'2017-12-24',35832.89,13,'Teresa Bautista',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-25 09:00:00','2026-07-20 14:59:08'),
(765,'COA-2019-076','Rice Thresher',9,5,'2019-02-02',126963.92,4,'Manuel Bautista',NULL,'Human Resource Management Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-04 09:00:00','2026-07-20 14:59:08'),
(766,'COA-2024-068','Service Vehicle (Sedan)',5,1,'2024-03-24',614924.49,10,'Danilo Cruz',1,'Municipal Engineering Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-25 09:00:00','2026-07-20 14:59:08'),
(767,'COA-2017-088','Backhoe Loader',6,1,'2017-08-03',2248189.43,15,'Juan Mendoza',NULL,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-04 09:00:00','2026-07-17 18:12:48'),
(768,'COA-2021-071','Weighing Scale (Digital)',8,1,'2021-04-19',6853.42,8,'Imelda Villanueva',1,'Assessor\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-20 09:00:00','2026-07-20 14:59:08'),
(769,'COA-2024-069','Nebulizer Machine',8,1,'2024-03-28',118790.48,16,'Josefa Ramos',1,'Information and Communications Technology Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-31 09:00:00','2026-07-20 14:59:08'),
(770,'COA-2017-089','Life Vest',10,1,'2017-04-06',65777.93,16,'Juan Garcia',1,'Information and Communications Technology Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-09 09:00:00','2026-07-20 14:59:08'),
(771,'COA-2018-073','CCTV DVR/NVR Unit',7,1,'2018-04-25',6294.14,12,NULL,NULL,'Municipal Health Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-27 09:00:00','2026-07-20 14:59:08'),
(772,'COA-2026-047','Bookshelf (Wooden, 5-Tier)',3,1,'2026-03-17',11679.50,9,'Ramon Villanueva',1,'Civil Registrar\'s Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2026-03-17 09:00:00','2026-07-17 18:12:48'),
(773,'COA-2022-071','Megaphone (Bullhorn)',7,1,'2022-05-10',36174.47,15,'Juan Salazar',1,'General Services Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-12 09:00:00','2026-07-20 14:59:08'),
(774,'COA-2024-070','Multi-Purpose Van',5,1,'2024-12-19',477286.70,3,'Luz Navarro',1,'Sangguniang Bayan Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-12-21 09:00:00','2026-07-17 18:12:48'),
(775,'COA-2018-074','Water Dispenser (Hot & Cold)',1,1,'2018-10-26',20886.46,2,'Leonora Rivera',1,'Office of the Vice Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-26 09:00:00','2026-07-17 18:12:48'),
(776,'COA-2018-075','Desktop Computer Set (Core i5)',2,1,'2018-06-15',43907.87,10,'Divina Del Rosario',1,'Municipal Engineering Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-18 09:00:00','2026-07-20 14:59:08'),
(777,'COA-2023-088','Life Vest',10,1,'2023-08-12',76807.36,14,'Ernesto Torres',1,'Municipal Agriculture Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-13 09:00:00','2026-07-17 18:12:48'),
(778,'COA-2020-049','Sprayer (Backpack, Motorized)',9,1,'2020-03-19',27964.64,6,'Antonio Rivera',1,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-20 09:00:00','2026-07-17 18:12:48'),
(779,'COA-2024-071','Base Radio Station',7,1,'2024-06-22',28646.36,3,'Elena Navarro',1,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-24 09:00:00','2026-07-20 14:59:08'),
(780,'COA-2023-089','Executive Office Desk',3,2,'2023-07-07',22840.49,13,NULL,2,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-09 09:00:00','2026-07-17 18:12:48'),
(781,'COA-2023-090','Multi-Purpose Van',5,1,'2023-09-29',1962549.72,16,'Eduardo Del Rosario',NULL,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-02 09:00:00','2026-07-17 18:12:48'),
(782,'COA-2019-077','Binding Machine',4,1,'2019-05-17',47586.81,5,NULL,NULL,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-19 09:00:00','2026-07-20 14:59:08'),
(783,'COA-2017-090','Bulletin Board (Cork, Framed)',4,1,'2017-02-28',4528.70,7,'Manuel Reyes',NULL,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-03 09:00:00','2026-07-17 18:12:48'),
(784,'COA-2025-062','Metal Detector (Handheld)',10,1,'2025-08-20',59395.74,15,'Rodrigo Dela Cruz',1,'General Services Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-20 09:00:00','2026-07-20 14:59:08'),
(785,'COA-2019-078','Weighing Scale (Digital)',8,1,'2019-03-31',115152.33,10,'Imelda Ramos',1,'Municipal Engineering Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-02 09:00:00','2026-07-20 14:59:08'),
(786,'COA-2016-074','Document Scanner',2,1,'2016-02-15',30615.40,13,'Romeo Del Rosario',NULL,'Municipal Social Welfare and Development Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-15 09:00:00','2026-07-20 14:59:08'),
(787,'COA-2020-050','Air Conditioning Unit (1.5HP Split Type)',1,1,'2020-01-05',20813.79,6,'Manuel Rivera',1,'Accounting Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-06 09:00:00','2026-07-17 18:12:48'),
(788,'COA-2024-072','Conference Table (8-Seater)',3,2,'2024-10-20',3028.03,9,'Josefa Domingo',2,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-23 09:00:00','2026-07-17 18:12:48'),
(789,'COA-2022-072','Grass Cutter (Riding Type)',6,1,'2022-07-22',2715175.86,12,'Juan Ocampo',1,'Municipal Health Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-22 09:00:00','2026-07-17 18:12:48'),
(790,'COA-2026-048','Typewriter (Manual)',4,1,'2026-02-02',48146.12,4,'Teresa Santos',1,'Human Resource Management Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-05 09:00:00','2026-07-20 14:59:08'),
(791,'COA-2019-079','Refrigerator (2-Door)',1,1,'2019-08-08',39183.10,6,'Rodrigo Navarro',1,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-10 09:00:00','2026-07-17 18:12:48'),
(792,'COA-2016-075','Seedling Tray Set',9,1,'2016-12-18',114538.91,7,'Carlos Reyes',1,'Treasury Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-20 09:00:00','2026-07-17 18:12:48'),
(793,'COA-2018-076','Rice Thresher',9,5,'2018-02-17',149567.12,16,'Carmen Cruz',NULL,'Information and Communications Technology Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-19 09:00:00','2026-07-20 14:59:08'),
(794,'COA-2019-080','Steel Filing Cabinet (4-Drawer)',3,1,'2019-05-06',14565.49,17,'Cecilia Castillo',NULL,'Disaster Risk Reduction and Management Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2019-05-07 09:00:00','2026-07-20 14:59:08'),
(795,'COA-2021-072','Motorcycle (Service Unit)',5,1,'2021-12-28',872447.20,3,'Corazon Rivera',1,'Sangguniang Bayan Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-31 09:00:00','2026-07-17 18:12:48'),
(796,'COA-2016-076','Multi-Purpose Van',5,1,'2016-05-12',1187459.97,1,'Romeo Reyes',NULL,'Office of the Mayor - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2016-05-13 09:00:00','2026-07-20 14:59:08'),
(797,'COA-2019-081','Laptop Computer (Business Series)',2,1,'2019-11-17',81092.81,2,'Corazon Santos',1,'Office of the Vice Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-18 09:00:00','2026-07-17 18:12:48'),
(798,'COA-2021-073','Bulldozer',6,1,'2021-05-10',2577394.24,14,NULL,NULL,'Municipal Agriculture Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-05-13 09:00:00','2026-07-17 18:12:48'),
(799,'COA-2023-091','Farm Tool Kit',9,1,'2023-08-25',101015.54,13,'Ernesto Domingo',NULL,'Municipal Social Welfare and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-25 09:00:00','2026-07-20 14:59:08'),
(800,'COA-2018-077','Bulldozer',6,1,'2018-03-04',1594095.77,12,'Elena Santos',NULL,'Municipal Health Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-03-05 09:00:00','2026-07-17 18:12:48'),
(801,'COA-2024-073','Hand Tractor',9,1,'2024-12-28',146927.76,2,'Pedro Pascual',NULL,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-12-28 09:00:00','2026-07-17 18:12:48'),
(802,'COA-2023-092','Handheld Two-Way Radio',7,1,'2023-05-17',30405.09,16,'Cecilia Torres',1,'Information and Communications Technology Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-19 09:00:00','2026-07-20 14:59:08'),
(803,'COA-2025-063','Generator Set (25 kVA)',6,1,'2025-09-29',1045986.51,10,NULL,NULL,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-02 09:00:00','2026-07-20 14:59:08'),
(804,'COA-2018-078','Service Pick-up Truck',5,1,'2018-04-13',1922494.37,3,'Luz Ocampo',1,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-13 09:00:00','2026-07-20 14:59:08'),
(805,'COA-2017-091','Digital Blood Pressure Monitor',8,1,'2017-04-12',60620.54,15,'Ramon Navarro',1,'General Services Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2017-04-15 09:00:00','2026-07-20 14:59:08'),
(806,'COA-2016-077','Base Radio Station',7,1,'2016-06-30',11243.53,15,'Teresa Gonzales',NULL,'General Services Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-30 09:00:00','2026-07-17 18:12:48'),
(807,'COA-2025-064','Concrete Mixer',6,1,'2025-01-31',2034232.09,9,'Antonio Ocampo',1,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-02-02 09:00:00','2026-07-17 18:12:48'),
(808,'COA-2025-065','CCTV Camera (Outdoor)',7,1,'2025-08-17',22198.86,10,'Eduardo Rivera',1,'Municipal Engineering Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2025-08-20 09:00:00','2026-07-17 18:12:48'),
(809,'COA-2024-074','UPS (Uninterruptible Power Supply)',2,1,'2024-08-25',30074.34,8,'Maria Cruz',1,'Assessor\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-28 09:00:00','2026-07-17 18:12:48'),
(810,'COA-2025-066','Life Vest',10,1,'2025-05-17',80826.12,11,'Juan Pascual',1,'Municipal Planning and Development Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2025-05-17 09:00:00','2026-07-20 14:59:08'),
(811,'COA-2016-078','Ambulance Unit',5,1,'2016-09-19',764656.84,11,'Ramon Ramos',1,'Municipal Planning and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-19 09:00:00','2026-07-20 14:59:08'),
(812,'COA-2023-093','Water Cooler/Dispenser',1,1,'2023-09-04',32944.26,6,'Danilo Flores',1,'Accounting Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2023-09-05 09:00:00','2026-07-20 14:59:08'),
(813,'COA-2016-079','Grass Cutter (Riding Type)',6,1,'2016-11-13',1614866.15,4,'Elena Torres',NULL,'Human Resource Management Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-16 09:00:00','2026-07-20 14:59:08'),
(814,'COA-2019-082','Water Tanker Truck',6,1,'2019-10-04',2907567.84,12,'Luz Cruz',1,'Municipal Health Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-06 09:00:00','2026-07-20 14:59:08'),
(815,'COA-2024-075','Concrete Mixer',6,1,'2024-01-10',2464823.74,17,'Danilo Aquino',NULL,'Disaster Risk Reduction and Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-12 09:00:00','2026-07-17 18:12:48'),
(816,'COA-2022-073','UPS (Uninterruptible Power Supply)',2,1,'2022-05-04',84829.41,8,'Norma Aguilar',1,'Assessor\'s Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-06 09:00:00','2026-07-20 14:59:08'),
(817,'COA-2018-079','Concrete Mixer',6,1,'2018-03-09',1989444.65,9,NULL,NULL,'Civil Registrar\'s Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-09 09:00:00','2026-07-20 14:59:08'),
(818,'COA-2024-076','Fax Machine',4,1,'2024-03-20',25436.63,15,'Ricardo Santos',1,'General Services Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-20 09:00:00','2026-07-17 18:12:48'),
(819,'COA-2024-077','Steel Locker Cabinet',3,5,'2024-09-15',19046.19,8,'Divina Villanueva',5,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-17 09:00:00','2026-07-17 18:12:48'),
(820,'COA-2025-067','Bulletin Board (Cork, Framed)',4,1,'2025-10-29',3961.76,6,'Ramon Gonzales',1,'Accounting Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-30 09:00:00','2026-07-20 14:59:08'),
(821,'COA-2025-068','Steel Locker Cabinet',3,2,'2025-09-20',10697.06,17,'Cecilia Flores',2,'Disaster Risk Reduction and Management Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-23 09:00:00','2026-07-17 18:12:48'),
(822,'COA-2024-078','Electric Kettle',1,1,'2024-04-13',52370.75,3,NULL,NULL,'Sangguniang Bayan Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-16 09:00:00','2026-07-17 18:12:48'),
(823,'COA-2016-080','Rescue Rope Kit',10,1,'2016-12-09',85290.72,17,'Carmen Del Rosario',NULL,'Disaster Risk Reduction and Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2016-12-09 09:00:00','2026-07-17 18:12:48'),
(824,'COA-2016-081','Autoclave Sterilizer',8,1,'2016-07-16',35302.98,11,'Ernesto Mendoza',NULL,'Municipal Planning and Development Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-07-17 09:00:00','2026-07-20 14:59:08'),
(825,'COA-2019-083','CCTV Camera (Outdoor)',7,1,'2019-02-13',39882.31,17,'Carmen Villanueva',1,'Disaster Risk Reduction and Management Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-16 09:00:00','2026-07-20 14:59:08'),
(826,'COA-2018-080','Dump Truck',5,1,'2018-08-06',937600.24,4,'Cecilia Rivera',1,'Human Resource Management Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-08-09 09:00:00','2026-07-20 14:59:08'),
(827,'COA-2021-074','Photocopier Machine (Multi-function)',4,1,'2021-06-23',25911.51,1,'Eduardo Aguilar',NULL,'Office of the Mayor - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-23 09:00:00','2026-07-20 14:59:08'),
(828,'COA-2021-075','Wheelchair',8,1,'2021-07-13',11793.36,14,'Ramon Ocampo',1,'Municipal Agriculture Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-15 09:00:00','2026-07-20 14:59:08'),
(829,'COA-2021-076','Generator Set (25 kVA)',6,1,'2021-01-31',2446236.97,9,'Jose Marquez',1,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-31 09:00:00','2026-07-20 14:59:08'),
(830,'COA-2023-094','Farm Tool Kit',9,1,'2023-02-11',46903.77,2,'Leonora Flores',1,'Office of the Vice Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-12 09:00:00','2026-07-20 14:59:08'),
(831,'COA-2025-069','All-in-One Inkjet Printer',2,1,'2025-08-11',7249.42,17,'Cecilia Cruz',1,'Disaster Risk Reduction and Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-13 09:00:00','2026-07-17 18:12:48'),
(832,'COA-2021-077','Generator Set (25 kVA)',6,1,'2021-12-12',3069855.38,16,NULL,1,'Information and Communications Technology Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-15 09:00:00','2026-07-17 18:12:48'),
(833,'COA-2018-081','Service Vehicle (Sedan)',5,1,'2018-06-15',2135108.16,4,NULL,1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-16 09:00:00','2026-07-17 18:12:48'),
(834,'COA-2023-095','LCD/LED Monitor 24\"',2,1,'2023-10-25',61975.87,12,'Josefa Salazar',NULL,'Municipal Health Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-26 09:00:00','2026-07-17 18:12:48'),
(835,'COA-2018-082','Electric Kettle',1,1,'2018-12-07',24089.53,11,'Teresa Domingo',NULL,'Municipal Planning and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-10 09:00:00','2026-07-17 18:12:48'),
(836,'COA-2022-074','Base Radio Station',7,1,'2022-06-02',25280.56,8,'Ana Cruz',NULL,'Assessor\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2022-06-03 09:00:00','2026-07-20 14:59:08'),
(837,'COA-2023-096','Backhoe Loader',6,1,'2023-05-06',1828149.65,3,'Carlos Mendoza',1,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-08 09:00:00','2026-07-17 18:12:48'),
(838,'COA-2016-082','Hand Tractor',9,1,'2016-02-25',136779.00,8,'Ricardo Domingo',1,'Assessor\'s Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-02-28 09:00:00','2026-07-17 18:12:48'),
(839,'COA-2019-084','Paper Shredder (Heavy Duty)',4,1,'2019-01-20',53405.74,2,'Manuel Garcia',NULL,'Office of the Vice Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2019-01-22 09:00:00','2026-07-17 18:12:48'),
(840,'COA-2018-083','Document Scanner',2,1,'2018-03-06',74025.64,13,'Teresa Rivera',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-08 09:00:00','2026-07-20 14:59:08'),
(841,'COA-2018-084','PABX Telephone System',7,1,'2018-06-29',26342.34,3,'Gloria Marquez',NULL,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-02 09:00:00','2026-07-20 14:59:08'),
(842,'COA-2018-085','Document Scanner',2,1,'2018-07-06',83064.87,15,'Elena Pascual',1,'General Services Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-07-06 09:00:00','2026-07-17 18:12:48'),
(843,'COA-2022-075','Calculator (Desktop Printing)',4,1,'2022-08-27',8201.10,16,'Alfredo Salazar',1,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-29 09:00:00','2026-07-17 18:12:48'),
(844,'COA-2016-083','Bulldozer',6,1,'2016-05-29',2313643.16,5,'Leonora Dela Cruz',1,'Budget Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-05-31 09:00:00','2026-07-20 14:59:08'),
(845,'COA-2023-097','Water Tanker Truck',6,1,'2023-12-13',1816128.68,15,NULL,1,'General Services Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-13 09:00:00','2026-07-20 14:59:08'),
(846,'COA-2018-086','External Hard Drive 2TB',2,1,'2018-03-19',74840.44,6,'Romeo Aguilar',1,'Accounting Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-19 09:00:00','2026-07-20 14:59:08'),
(847,'COA-2020-051','Multi-Purpose Van',5,1,'2020-11-18',1709900.24,4,NULL,1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-18 09:00:00','2026-07-17 18:12:48'),
(848,'COA-2021-078','Binding Machine',4,1,'2021-10-28',32270.82,12,'Antonio Ocampo',1,'Municipal Health Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-10-31 09:00:00','2026-07-17 18:12:48'),
(849,'COA-2023-098','Air Conditioning Unit (1.5HP Split Type)',1,1,'2023-11-13',12961.55,10,'Francisco Castillo',1,'Municipal Engineering Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-11-15 09:00:00','2026-07-17 18:12:48'),
(850,'COA-2019-085','Farm Tool Kit',9,1,'2019-11-13',167270.73,8,'Alfredo Aguilar',1,'Assessor\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-16 09:00:00','2026-07-17 18:12:48'),
(851,'COA-2022-076','Typewriter (Manual)',4,1,'2022-08-24',9384.53,3,'Rosa Ramos',NULL,'Sangguniang Bayan Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-25 09:00:00','2026-07-17 18:12:48'),
(852,'COA-2018-087','Service Pick-up Truck',5,1,'2018-05-07',454673.87,16,'Carlos Santos',1,'Information and Communications Technology Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-08 09:00:00','2026-07-20 14:59:08'),
(853,'COA-2025-070','Partition Divider Panel',3,2,'2025-01-19',19017.77,17,'Ricardo Bautista',2,'Disaster Risk Reduction and Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-20 09:00:00','2026-07-17 18:12:48'),
(854,'COA-2025-071','Seedling Tray Set',9,1,'2025-11-26',172121.06,3,NULL,NULL,'Sangguniang Bayan Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-29 09:00:00','2026-07-20 14:59:08'),
(855,'COA-2023-099','Water Pump (Irrigation)',9,1,'2023-04-24',7964.67,14,'Francisco Del Rosario',NULL,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-27 09:00:00','2026-07-17 18:12:48'),
(856,'COA-2018-088','Partition Divider Panel',3,1,'2018-03-13',15296.87,1,'Luz Castillo',1,'Office of the Mayor - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-13 09:00:00','2026-07-20 14:59:08'),
(857,'COA-2016-084','Wheelchair',8,1,'2016-06-28',33989.60,13,'Eduardo Dela Cruz',NULL,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-28 09:00:00','2026-07-17 18:12:48'),
(858,'COA-2020-052','Desktop Computer Set (Core i5)',2,1,'2020-02-22',54807.80,2,'Danilo Ocampo',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-22 09:00:00','2026-07-17 18:12:48'),
(859,'COA-2017-092','Microwave Oven',1,1,'2017-02-03',54128.68,11,'Corazon Ocampo',NULL,'Municipal Planning and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-06 09:00:00','2026-07-20 14:59:08'),
(860,'COA-2016-085','Generator Set (25 kVA)',6,1,'2016-02-28',1499043.29,17,'Imelda Reyes',1,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2016-03-01 09:00:00','2026-07-20 14:59:08'),
(861,'COA-2017-093','Farm Tool Kit',9,1,'2017-12-09',58420.54,14,'Ana Castillo',1,'Municipal Agriculture Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2017-12-09 09:00:00','2026-07-17 18:12:48'),
(862,'COA-2022-077','Executive Office Desk',3,1,'2022-08-18',22338.14,11,'Carmen Pascual',NULL,'Municipal Planning and Development Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-19 09:00:00','2026-07-20 14:59:08'),
(863,'COA-2016-086','Steel Locker Cabinet',3,1,'2016-08-06',5970.51,10,'Antonio Aguilar',1,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-08 09:00:00','2026-07-17 18:12:48'),
(864,'COA-2019-086','Document Scanner',2,1,'2019-12-25',35361.83,16,'Ricardo Pascual',1,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-12-26 09:00:00','2026-07-20 14:59:08'),
(865,'COA-2019-087','Binding Machine',4,1,'2019-11-21',15861.71,14,'Ricardo Gonzales',1,'Municipal Agriculture Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-24 09:00:00','2026-07-17 18:12:48'),
(866,'COA-2021-079','Rice Thresher',9,2,'2021-04-30',107073.86,6,'Manuel Del Rosario',NULL,'Accounting Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-01 09:00:00','2026-07-20 14:59:08'),
(867,'COA-2019-088','Weighing Scale (Digital)',8,1,'2019-10-11',23672.71,11,'Rosa Pascual',1,'Municipal Planning and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-11 09:00:00','2026-07-20 14:59:08'),
(868,'COA-2025-072','Base Radio Station',7,1,'2025-05-09',13234.43,16,'Antonio Salazar',1,'Information and Communications Technology Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-12 09:00:00','2026-07-20 14:59:08'),
(869,'COA-2022-078','Fire Extinguisher (10lbs)',10,1,'2022-08-26',17254.41,13,'Luz Cruz',1,'Municipal Social Welfare and Development Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-28 09:00:00','2026-07-20 14:59:08'),
(870,'COA-2024-079','Laser Printer (Monochrome)',2,1,'2024-11-21',69516.19,10,'Rosa Pascual',1,'Municipal Engineering Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-22 09:00:00','2026-07-17 18:12:48'),
(871,'COA-2024-080','Base Radio Station',7,1,'2024-02-14',9050.86,3,'Ernesto Aquino',1,'Sangguniang Bayan Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-15 09:00:00','2026-07-17 18:12:48'),
(872,'COA-2023-100','Base Radio Station',7,1,'2023-12-02',34929.89,15,'Pedro Castillo',NULL,'General Services Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-03 09:00:00','2026-07-17 18:12:48'),
(873,'COA-2019-089','Sprayer (Backpack, Motorized)',9,5,'2019-11-21',8247.19,3,NULL,5,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-22 09:00:00','2026-07-17 18:12:48'),
(874,'COA-2017-094','External Hard Drive 2TB',2,1,'2017-07-19',21661.70,8,'Teresa Santos',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-21 09:00:00','2026-07-17 18:12:48'),
(875,'COA-2018-089','Service Pick-up Truck',5,1,'2018-01-05',1146878.25,14,'Ana Pascual',NULL,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-06 09:00:00','2026-07-17 18:12:48'),
(876,'COA-2020-053','Partition Divider Panel',3,1,'2020-04-21',14228.54,17,NULL,1,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-23 09:00:00','2026-07-17 18:12:48'),
(877,'COA-2020-054','Thermal Scanner',8,1,'2020-03-07',85874.78,17,'Carmen Bautista',1,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-07 09:00:00','2026-07-17 18:12:48'),
(878,'COA-2018-090','Chainsaw (Rescue Type)',10,1,'2018-03-20',77593.67,9,'Francisco Aguilar',1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-23 09:00:00','2026-07-20 14:59:08'),
(879,'COA-2020-055','Bulldozer',6,1,'2020-10-09',2273739.40,9,'Juan Gonzales',1,'Civil Registrar\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-11 09:00:00','2026-07-20 14:59:08'),
(880,'COA-2021-080','Generator Set (25 kVA)',6,1,'2021-12-16',1479211.52,2,'Cecilia Bautista',NULL,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-19 09:00:00','2026-07-17 18:12:48'),
(881,'COA-2022-079','Bulletin Board (Cork, Framed)',4,1,'2022-05-19',5519.74,17,'Maria Garcia',1,'Disaster Risk Reduction and Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-22 09:00:00','2026-07-20 14:59:08'),
(882,'COA-2020-056','Water Tanker Truck',6,1,'2020-09-26',413792.90,10,NULL,NULL,'Municipal Engineering Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-26 09:00:00','2026-07-20 14:59:08'),
(883,'COA-2019-090','Chainsaw (Rescue Type)',10,1,'2019-05-26',49805.68,9,NULL,NULL,'Civil Registrar\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-29 09:00:00','2026-07-17 18:12:48'),
(884,'COA-2021-081','Executive Office Desk',3,5,'2021-08-16',11884.37,9,'Luz Ramos',5,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-19 09:00:00','2026-07-17 18:12:48'),
(885,'COA-2018-091','Road Roller',6,1,'2018-06-25',401507.83,4,'Jose Cruz',1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-27 09:00:00','2026-07-17 18:12:48'),
(886,'COA-2019-091','Nebulizer Machine',8,1,'2019-11-05',39377.67,1,'Pedro Pascual',1,'Office of the Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-08 09:00:00','2026-07-17 18:12:48'),
(887,'COA-2022-080','24-Port Network Switch',2,1,'2022-04-18',13481.18,16,'Ricardo Aquino',1,'Information and Communications Technology Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-04-19 09:00:00','2026-07-17 18:12:48'),
(888,'COA-2024-081','IP Desk Phone',7,1,'2024-06-04',26148.68,1,'Elena Domingo',1,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-05 09:00:00','2026-07-20 14:59:08'),
(889,'COA-2018-092','Laser Printer (Monochrome)',2,1,'2018-01-01',66816.22,10,NULL,1,'Municipal Engineering Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-03 09:00:00','2026-07-17 18:12:48'),
(890,'COA-2021-082','UPS (Uninterruptible Power Supply)',2,1,'2021-08-19',48535.66,11,'Manuel Salazar',1,'Municipal Planning and Development Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2021-08-21 09:00:00','2026-07-20 14:59:08'),
(891,'COA-2023-101','Weighing Scale (Digital)',8,1,'2023-08-31',46927.38,6,'Teresa Aguilar',NULL,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-01 09:00:00','2026-07-20 14:59:08'),
(892,'COA-2019-092','CCTV Camera (Outdoor)',7,1,'2019-08-24',13122.48,1,'Josefa Del Rosario',1,'Office of the Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-27 09:00:00','2026-07-17 18:12:48'),
(893,'COA-2021-083','Laminating Machine',4,1,'2021-02-18',47829.73,6,'Josefa Marquez',1,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-21 09:00:00','2026-07-20 14:59:08'),
(894,'COA-2018-093','Emergency Light Tower',10,1,'2018-09-17',18449.64,15,'Rodrigo Bautista',1,'General Services Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-17 09:00:00','2026-07-20 14:59:08'),
(895,'COA-2023-102','Vacuum Cleaner',1,1,'2023-08-25',48020.79,2,NULL,NULL,'Office of the Vice Mayor - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-08-28 09:00:00','2026-07-17 18:12:48'),
(896,'COA-2020-057','External Hard Drive 2TB',2,1,'2020-12-01',71564.80,1,'Divina Domingo',1,'Office of the Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-12-02 09:00:00','2026-07-17 18:12:48'),
(897,'COA-2024-082','Steel Filing Cabinet (4-Drawer)',3,1,'2024-07-01',11021.25,9,'Pedro Flores',NULL,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-02 09:00:00','2026-07-17 18:12:48'),
(898,'COA-2023-103','Water Tanker Truck',6,1,'2023-09-23',1292384.46,10,'Ramon Navarro',1,'Municipal Engineering Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-25 09:00:00','2026-07-20 14:59:08'),
(899,'COA-2019-093','Generator Set (25 kVA)',6,1,'2019-06-10',801161.97,10,'Josefa Marquez',1,'Municipal Engineering Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-10 09:00:00','2026-07-20 14:59:08'),
(900,'COA-2023-104','Base Radio Station',7,1,'2023-02-21',3690.20,9,'Luz Garcia',NULL,'Civil Registrar\'s Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-02-22 09:00:00','2026-07-17 18:12:48'),
(901,'COA-2021-084','Seedling Tray Set',9,1,'2021-05-07',175129.18,13,'Eduardo Rivera',NULL,'Municipal Social Welfare and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-08 09:00:00','2026-07-20 14:59:08'),
(902,'COA-2016-087','Weighing Scale (Digital)',8,1,'2016-02-28',42070.49,13,'Elena Garcia',1,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-02 09:00:00','2026-07-20 14:59:08'),
(903,'COA-2026-049','Air Conditioning Unit (1.5HP Split Type)',1,1,'2026-01-26',41422.34,17,'Maria Domingo',NULL,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-27 09:00:00','2026-07-17 18:12:48'),
(904,'COA-2021-085','Document Scanner',2,1,'2021-01-03',47790.01,2,'Divina Ocampo',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2021-01-06 09:00:00','2026-07-17 18:12:48'),
(905,'COA-2017-095','Farm Tool Kit',9,1,'2017-01-09',132934.02,9,NULL,1,'Civil Registrar\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-09 09:00:00','2026-07-17 18:12:48'),
(906,'COA-2019-094','Farm Tool Kit',9,1,'2019-07-30',38169.16,2,'Jose Salazar',1,'Office of the Vice Mayor - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-01 09:00:00','2026-07-20 14:59:08'),
(907,'COA-2024-083','All-in-One Inkjet Printer',2,1,'2024-09-19',52937.13,15,'Ernesto Pascual',1,'General Services Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-20 09:00:00','2026-07-17 18:12:48'),
(908,'COA-2018-094','Patrol Motorcycle',5,1,'2018-12-18',1381332.55,10,'Imelda Gonzales',1,'Municipal Engineering Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-21 09:00:00','2026-07-20 14:59:08'),
(909,'COA-2021-086','Rice Thresher',9,1,'2021-07-23',15071.25,16,'Luz Bautista',NULL,'Information and Communications Technology Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-26 09:00:00','2026-07-20 14:59:08'),
(910,'COA-2021-087','Binding Machine',4,1,'2021-08-17',22840.98,10,'Ana Del Rosario',1,'Municipal Engineering Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-20 09:00:00','2026-07-17 18:12:48'),
(911,'COA-2022-081','Swivel Office Chair',3,1,'2022-11-04',26839.75,6,NULL,1,'Accounting Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-07 09:00:00','2026-07-20 14:59:08'),
(912,'COA-2017-096','Multi-Purpose Van',5,1,'2017-08-16',1034013.79,12,'Norma Castillo',1,'Municipal Health Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-16 09:00:00','2026-07-17 18:12:48'),
(913,'COA-2024-084','Conference Table (8-Seater)',3,1,'2024-08-07',23136.69,15,'Imelda Marquez',1,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-07 09:00:00','2026-07-17 18:12:48'),
(914,'COA-2022-082','Bulletin Board (Cork, Framed)',4,1,'2022-12-04',56097.01,7,'Elena Mendoza',NULL,'Treasury Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-07 09:00:00','2026-07-20 14:59:08'),
(915,'COA-2018-095','IP Desk Phone',7,1,'2018-10-20',44444.49,16,'Maria Bautista',1,'Information and Communications Technology Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-22 09:00:00','2026-07-17 18:12:48'),
(916,'COA-2024-085','LCD/LED Monitor 24\"',2,1,'2024-09-10',71296.23,11,NULL,1,'Municipal Planning and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-13 09:00:00','2026-07-20 14:59:08'),
(917,'COA-2025-073','Multi-Purpose Van',5,1,'2025-03-01',1656747.73,17,'Ernesto Santos',1,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-03 09:00:00','2026-07-17 18:12:48'),
(918,'COA-2020-058','Laminating Machine',4,1,'2020-01-23',15337.08,15,NULL,1,'General Services Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-24 09:00:00','2026-07-20 14:59:08'),
(919,'COA-2025-074','Digital Blood Pressure Monitor',8,1,'2025-04-29',109688.39,2,'Juan Navarro',NULL,'Office of the Vice Mayor - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-29 09:00:00','2026-07-20 14:59:08'),
(920,'COA-2023-105','Fire Extinguisher (10lbs)',10,1,'2023-02-11',70302.34,11,'Cecilia Bautista',1,'Municipal Planning and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-11 09:00:00','2026-07-20 14:59:08'),
(921,'COA-2025-075','Wireless Router',2,1,'2025-03-03',43325.78,14,NULL,1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-03 09:00:00','2026-07-17 18:12:48'),
(922,'COA-2020-059','CCTV Camera (Outdoor)',7,1,'2020-07-02',14987.09,1,'Manuel Dela Cruz',1,'Office of the Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-03 09:00:00','2026-07-17 18:12:48'),
(923,'COA-2024-086','Nebulizer Machine',8,1,'2024-08-19',107349.36,7,'Eduardo Garcia',NULL,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-20 09:00:00','2026-07-17 18:12:48'),
(924,'COA-2025-076','24-Port Network Switch',2,1,'2025-10-05',79420.31,11,'Carlos Villanueva',1,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-08 09:00:00','2026-07-20 14:59:08'),
(925,'COA-2025-077','Autoclave Sterilizer',8,1,'2025-05-09',4512.73,4,NULL,1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-11 09:00:00','2026-07-17 18:12:48'),
(926,'COA-2021-088','Document Scanner',2,1,'2021-09-06',63512.43,6,'Ernesto Torres',1,'Accounting Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-06 09:00:00','2026-07-20 14:59:08'),
(927,'COA-2020-060','External Hard Drive 2TB',2,1,'2020-01-13',26912.19,17,'Francisco Dela Cruz',1,'Disaster Risk Reduction and Management Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-14 09:00:00','2026-07-20 14:59:08'),
(928,'COA-2025-078','Wireless Router',2,1,'2025-07-04',24889.99,14,'Rodrigo Fernandez',NULL,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2025-07-07 09:00:00','2026-07-20 14:59:08'),
(929,'COA-2017-097','Swivel Office Chair',3,1,'2017-06-08',19827.88,1,'Maria Cruz',1,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-08 09:00:00','2026-07-17 18:12:48'),
(930,'COA-2024-087','Farm Tool Kit',9,1,'2024-04-27',67934.50,5,NULL,1,'Budget Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-04-29 09:00:00','2026-07-20 12:47:01'),
(931,'COA-2016-088','Patrol Motorcycle',5,1,'2016-04-26',495202.56,11,'Josefa Reyes',1,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-04-29 09:00:00','2026-07-17 18:12:48'),
(932,'COA-2026-050','Air Conditioning Unit (1.5HP Split Type)',1,1,'2026-01-22',7336.50,12,NULL,1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-22 09:00:00','2026-07-17 18:12:48'),
(933,'COA-2021-089','Water Cooler/Dispenser',1,1,'2021-05-04',49726.32,10,'Antonio Del Rosario',NULL,'Municipal Engineering Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-05 09:00:00','2026-07-17 18:12:48'),
(934,'COA-2018-096','Typewriter (Manual)',4,1,'2018-06-17',52937.74,5,'Imelda Santos',1,'Budget Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-17 09:00:00','2026-07-20 12:47:01'),
(935,'COA-2023-106','Ambulance Unit',5,1,'2023-12-20',1619623.64,11,'Eduardo Ramos',NULL,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-21 09:00:00','2026-07-20 14:59:08'),
(936,'COA-2024-088','Base Radio Station',7,1,'2024-11-27',44130.05,2,'Rodrigo Reyes',1,'Office of the Vice Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-28 09:00:00','2026-07-17 18:12:48'),
(937,'COA-2021-090','Rescue Rope Kit',10,1,'2021-01-25',44147.00,13,'Francisco Bautista',1,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-28 09:00:00','2026-07-17 18:12:48'),
(938,'COA-2023-107','Weighing Scale (Digital)',8,1,'2023-06-09',80659.50,15,'Ricardo Ramos',1,'General Services Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-09 09:00:00','2026-07-20 14:59:08'),
(939,'COA-2022-083','Wireless Router',2,1,'2022-03-04',16851.34,4,'Francisco Aguilar',1,'Human Resource Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-06 09:00:00','2026-07-20 14:59:08'),
(940,'COA-2017-098','Farm Tool Kit',9,1,'2017-08-03',140448.36,7,'Norma Aquino',NULL,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-04 09:00:00','2026-07-20 14:59:08'),
(941,'COA-2017-099','Laminating Machine',4,1,'2017-11-14',12842.49,17,'Rodrigo Fernandez',NULL,'Disaster Risk Reduction and Management Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-14 09:00:00','2026-07-20 14:59:08'),
(942,'COA-2016-089','Fax Machine',4,1,'2016-07-19',21382.78,9,NULL,1,'Civil Registrar\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-20 09:00:00','2026-07-20 14:59:08'),
(943,'COA-2018-097','Farm Tool Kit',9,5,'2018-05-05',108338.34,10,'Ernesto Aguilar',NULL,'Municipal Engineering Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-08 09:00:00','2026-07-20 14:59:08'),
(944,'COA-2020-061','Visitor\'s Chair (Stackable)',3,1,'2020-05-20',23560.02,14,'Ramon Garcia',1,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-22 09:00:00','2026-07-20 14:59:08'),
(945,'COA-2023-108','Backhoe Loader',6,1,'2023-02-21',1833767.80,1,'Ernesto Fernandez',NULL,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-24 09:00:00','2026-07-17 18:12:48'),
(946,'COA-2025-079','Wireless Router',2,1,'2025-10-24',81060.06,11,'Alfredo Ramos',NULL,'Municipal Planning and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-25 09:00:00','2026-07-17 18:12:48'),
(947,'COA-2021-091','Service Vehicle (Sedan)',5,1,'2021-11-11',605002.67,8,'Corazon Aquino',1,'Assessor\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-11-14 09:00:00','2026-07-20 14:59:08'),
(948,'COA-2026-051','Multi-Purpose Van',5,1,'2026-02-22',1570464.49,9,'Imelda Ramos',1,'Civil Registrar\'s Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2026-02-23 09:00:00','2026-07-17 18:12:48'),
(949,'COA-2022-084','Autoclave Sterilizer',8,1,'2022-08-18',80376.98,8,'Ernesto Marquez',NULL,'Assessor\'s Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-19 09:00:00','2026-07-20 14:59:08'),
(950,'COA-2022-085','Emergency Light Tower',10,1,'2022-08-15',75804.80,4,NULL,1,'Human Resource Management Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-16 09:00:00','2026-07-20 14:59:08'),
(951,'COA-2024-089','CCTV DVR/NVR Unit',7,1,'2024-01-21',4194.26,13,'Francisco Pascual',NULL,'Municipal Social Welfare and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-24 09:00:00','2026-07-17 18:12:48'),
(952,'COA-2022-086','Water Dispenser (Hot & Cold)',1,1,'2022-05-11',3767.58,7,NULL,NULL,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-13 09:00:00','2026-07-20 14:59:08'),
(953,'COA-2018-098','Bulldozer',6,1,'2018-10-15',1621119.92,12,'Francisco Marquez',1,'Municipal Health Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-17 09:00:00','2026-07-17 18:12:48'),
(954,'COA-2025-080','Water Tanker Truck',6,1,'2025-06-21',2791442.12,6,'Corazon Gonzales',1,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-06-23 09:00:00','2026-07-20 14:59:08'),
(955,'COA-2024-090','Autoclave Sterilizer',8,1,'2024-06-25',25454.67,6,NULL,NULL,'Accounting Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-26 09:00:00','2026-07-20 14:59:08'),
(956,'COA-2022-087','Wireless Router',2,1,'2022-07-11',77888.77,7,'Cecilia Villanueva',1,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-14 09:00:00','2026-07-17 18:12:48'),
(957,'COA-2017-100','CCTV DVR/NVR Unit',7,1,'2017-08-20',16956.97,9,'Pedro Domingo',1,'Civil Registrar\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-23 09:00:00','2026-07-20 14:59:08'),
(958,'COA-2020-062','Concrete Mixer',6,1,'2020-12-17',466202.60,8,'Imelda Ramos',1,'Assessor\'s Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-12-18 09:00:00','2026-07-17 18:12:48'),
(959,'COA-2016-090','Binding Machine',4,1,'2016-02-20',18108.17,5,'Corazon Salazar',NULL,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-21 09:00:00','2026-07-20 12:47:01'),
(960,'COA-2024-091','Life Vest',10,1,'2024-05-16',67727.37,13,NULL,1,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2024-05-17 09:00:00','2026-07-20 14:59:08'),
(961,'COA-2024-092','Grass Cutter (Riding Type)',6,1,'2024-12-02',2000031.63,8,'Gloria Rivera',NULL,'Assessor\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-12-05 09:00:00','2026-07-20 14:59:08'),
(962,'COA-2021-092','Water Pump (Irrigation)',9,5,'2021-03-20',151162.27,8,'Francisco Salazar',5,'Assessor\'s Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2021-03-21 09:00:00','2026-07-20 14:59:08'),
(963,'COA-2016-091','Nebulizer Machine',8,1,'2016-09-18',9251.41,5,'Eduardo Ramos',NULL,'Budget Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-19 09:00:00','2026-07-20 12:47:01'),
(964,'COA-2022-088','Wheelchair',8,1,'2022-01-14',40668.19,10,'Romeo Rivera',1,'Municipal Engineering Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-16 09:00:00','2026-07-17 18:12:48'),
(965,'COA-2024-093','Backhoe Loader',6,1,'2024-09-07',2099473.81,4,'Norma Mendoza',1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-07 09:00:00','2026-07-17 18:12:48'),
(966,'COA-2019-095','Weighing Scale (Digital)',8,1,'2019-09-21',12658.13,4,'Danilo Del Rosario',1,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-24 09:00:00','2026-07-17 18:12:48'),
(967,'COA-2025-081','Conference Table (8-Seater)',3,2,'2025-11-09',3631.68,14,'Carlos Flores',2,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2025-11-10 09:00:00','2026-07-17 18:12:48'),
(968,'COA-2023-109','Water Pump (Irrigation)',9,1,'2023-08-28',33242.56,2,NULL,NULL,'Office of the Vice Mayor - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-08-28 09:00:00','2026-07-17 18:12:48'),
(969,'COA-2025-082','Fire Extinguisher (10lbs)',10,1,'2025-08-20',90881.19,12,'Corazon Salazar',1,'Municipal Health Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-22 09:00:00','2026-07-20 14:59:08'),
(970,'COA-2023-110','Swivel Office Chair',3,5,'2023-12-03',5189.17,15,'Juan Cruz',NULL,'General Services Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-03 09:00:00','2026-07-20 14:59:08'),
(971,'COA-2023-111','Laser Printer (Monochrome)',2,1,'2023-08-29',53028.29,12,'Ana Salazar',NULL,'Municipal Health Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-01 09:00:00','2026-07-20 14:59:08'),
(972,'COA-2017-101','CCTV DVR/NVR Unit',7,1,'2017-04-21',26064.63,15,'Carmen Garcia',NULL,'General Services Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-21 09:00:00','2026-07-17 18:12:48'),
(973,'COA-2025-083','Chainsaw (Rescue Type)',10,1,'2025-07-04',10458.67,4,'Gloria Rivera',1,'Human Resource Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-04 09:00:00','2026-07-17 18:12:48'),
(974,'COA-2019-096','Autoclave Sterilizer',8,1,'2019-04-14',49402.21,7,'Josefa Dela Cruz',NULL,'Treasury Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-14 09:00:00','2026-07-20 14:59:08'),
(975,'COA-2025-084','Electric Fan (Stand Type)',1,1,'2025-04-27',12374.14,17,'Romeo Navarro',1,'Disaster Risk Reduction and Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-27 09:00:00','2026-07-17 18:12:48'),
(976,'COA-2022-089','Photocopier Machine (Multi-function)',4,1,'2022-01-11',54072.26,12,'Teresa Ocampo',NULL,'Municipal Health Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2022-01-13 09:00:00','2026-07-17 18:12:48'),
(977,'COA-2016-092','Calculator (Desktop Printing)',4,1,'2016-10-25',33707.06,11,'Corazon Dela Cruz',1,'Municipal Planning and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-25 09:00:00','2026-07-17 18:12:48'),
(978,'COA-2020-063','Concrete Mixer',6,1,'2020-05-16',1000859.70,6,NULL,1,'Accounting Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-05-17 09:00:00','2026-07-17 18:12:48'),
(979,'COA-2018-099','CCTV DVR/NVR Unit',7,1,'2018-04-19',33806.93,10,'Danilo Dela Cruz',NULL,'Municipal Engineering Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-20 09:00:00','2026-07-20 14:59:08'),
(980,'COA-2023-112','Metal Detector (Handheld)',10,1,'2023-01-10',38778.57,1,'Francisco Garcia',NULL,'Office of the Mayor - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-01-13 09:00:00','2026-07-17 18:12:48'),
(981,'COA-2022-090','24-Port Network Switch',2,1,'2022-01-08',20054.61,6,'Imelda Marquez',1,'Accounting Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-09 09:00:00','2026-07-20 14:59:08'),
(982,'COA-2022-091','Bulletin Board (Cork, Framed)',4,1,'2022-03-22',15448.87,3,'Maria Salazar',NULL,'Sangguniang Bayan Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-25 09:00:00','2026-07-20 14:59:08'),
(983,'COA-2022-092','Laminating Machine',4,1,'2022-11-25',30162.73,14,'Corazon Reyes',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-26 09:00:00','2026-07-17 18:12:48'),
(984,'COA-2017-102','Bulldozer',6,1,'2017-12-19',1666800.97,9,NULL,1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-21 09:00:00','2026-07-17 18:12:48'),
(985,'COA-2025-085','Thermal Scanner',8,1,'2025-10-08',9721.87,1,'Ricardo Villanueva',1,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-10 09:00:00','2026-07-17 18:12:48'),
(986,'COA-2024-094','Electric Kettle',1,1,'2024-02-13',21944.54,6,'Ana Del Rosario',1,'Accounting Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-02-15 09:00:00','2026-07-17 18:12:48'),
(987,'COA-2025-086','Rescue Rope Kit',10,1,'2025-08-11',72882.39,4,'Cecilia Santos',1,'Human Resource Management Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-12 09:00:00','2026-07-17 18:12:48'),
(988,'COA-2023-113','Thermal Scanner',8,1,'2023-08-29',74094.11,8,'Rodrigo Pascual',1,'Assessor\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-30 09:00:00','2026-07-17 18:12:48'),
(989,'COA-2018-100','Swivel Office Chair',3,1,'2018-11-19',21032.15,13,'Luz Garcia',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-22 09:00:00','2026-07-17 18:12:48'),
(990,'COA-2020-064','Water Tanker Truck',6,1,'2020-07-20',2868322.11,7,'Francisco Pascual',1,'Treasury Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-22 09:00:00','2026-07-17 18:12:48'),
(991,'COA-2025-087','Laminating Machine',4,1,'2025-10-18',58821.97,7,'Ernesto Aguilar',1,'Treasury Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-20 09:00:00','2026-07-20 14:59:08'),
(992,'COA-2016-093','Rescue Rope Kit',10,1,'2016-07-27',22197.57,14,'Rosa Del Rosario',1,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-28 09:00:00','2026-07-20 14:59:08'),
(993,'COA-2023-114','Ambulance Unit',5,1,'2023-03-11',1456371.00,5,'Pedro Aguilar',1,'Budget Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-14 09:00:00','2026-07-20 14:59:08'),
(994,'COA-2024-095','Metal Detector (Handheld)',10,1,'2024-03-30',83460.24,17,'Divina Santos',1,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-04-02 09:00:00','2026-07-20 14:59:08'),
(995,'COA-2026-052','24-Port Network Switch',2,1,'2026-02-10',22834.55,11,'Carlos Villanueva',1,'Municipal Planning and Development Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-11 09:00:00','2026-07-20 14:59:08'),
(996,'COA-2017-103','Patrol Motorcycle',5,1,'2017-02-19',1433303.22,10,NULL,1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-20 09:00:00','2026-07-20 14:59:08'),
(997,'COA-2023-115','Stretcher (Foldable)',8,1,'2023-09-27',117170.78,9,'Pedro Pascual',1,'Civil Registrar\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2023-09-30 09:00:00','2026-07-17 18:12:48'),
(998,'COA-2021-093','Digital Blood Pressure Monitor',8,1,'2021-01-06',116480.16,6,NULL,1,'Accounting Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-07 09:00:00','2026-07-20 14:59:08'),
(999,'COA-2017-104','Megaphone (Bullhorn)',7,1,'2017-03-30',43317.61,5,'Rodrigo Castillo',NULL,'Budget Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2017-03-31 09:00:00','2026-07-20 14:59:08'),
(1000,'COA-2025-088','Conference Table (8-Seater)',3,1,'2025-07-18',14959.73,12,NULL,1,'Municipal Health Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-19 09:00:00','2026-07-20 14:59:08'),
(1001,'COA-2016-094','IP Desk Phone',7,1,'2016-06-14',34374.90,11,'Francisco Del Rosario',NULL,'Municipal Planning and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2016-06-14 09:00:00','2026-07-20 14:59:08'),
(1002,'COA-2020-065','Fax Machine',4,1,'2020-04-05',5230.96,16,'Danilo Domingo',NULL,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-07 09:00:00','2026-07-20 14:59:08'),
(1003,'COA-2022-093','Road Roller',6,1,'2022-03-12',1743166.70,9,'Gloria Pascual',1,'Civil Registrar\'s Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-14 09:00:00','2026-07-20 14:59:08'),
(1004,'COA-2016-095','Laser Printer (Monochrome)',2,1,'2016-10-31',36124.29,8,'Divina Flores',NULL,'Assessor\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-01 09:00:00','2026-07-20 14:59:08'),
(1005,'COA-2023-116','Bookshelf (Wooden, 5-Tier)',3,1,'2023-01-28',17616.75,15,'Pedro Torres',1,'General Services Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-29 09:00:00','2026-07-20 14:59:08'),
(1006,'COA-2019-097','UPS (Uninterruptible Power Supply)',2,1,'2019-08-05',22025.81,13,'Danilo Salazar',NULL,'Municipal Social Welfare and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-07 09:00:00','2026-07-17 18:12:48'),
(1007,'COA-2016-096','Rice Thresher',9,1,'2016-11-21',49965.67,1,NULL,NULL,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-21 09:00:00','2026-07-17 18:12:48'),
(1008,'COA-2020-066','Binding Machine',4,1,'2020-06-04',40296.35,6,'Luz Torres',1,'Accounting Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-06-04 09:00:00','2026-07-17 18:12:48'),
(1009,'COA-2021-094','Electric Kettle',1,1,'2021-07-16',49891.41,3,'Ernesto Aguilar',1,'Sangguniang Bayan Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-19 09:00:00','2026-07-20 14:59:08'),
(1010,'COA-2022-094','Bulldozer',6,1,'2022-05-20',2422374.44,3,'Carmen Ocampo',NULL,'Sangguniang Bayan Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-21 09:00:00','2026-07-17 18:12:48'),
(1011,'COA-2023-117','Bookshelf (Wooden, 5-Tier)',3,2,'2023-09-30',13660.52,2,'Gloria Domingo',2,'Office of the Vice Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-01 09:00:00','2026-07-17 18:12:48'),
(1012,'COA-2020-067','Swivel Office Chair',3,2,'2020-04-11',11001.03,11,'Alfredo Del Rosario',2,'Municipal Planning and Development Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-14 09:00:00','2026-07-20 14:59:08'),
(1013,'COA-2020-068','Water Dispenser (Hot & Cold)',1,1,'2020-05-25',18434.91,16,NULL,1,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-27 09:00:00','2026-07-17 18:12:48'),
(1014,'COA-2019-098','Weighing Scale (Digital)',8,1,'2019-12-18',9428.37,2,'Josefa Cruz',1,'Office of the Vice Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-20 09:00:00','2026-07-17 18:12:48'),
(1015,'COA-2023-118','Conference Table (8-Seater)',3,5,'2023-01-26',12697.13,11,'Pedro Rivera',5,'Municipal Planning and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-26 09:00:00','2026-07-17 18:12:48'),
(1016,'COA-2020-069','Vacuum Cleaner',1,1,'2020-02-24',15420.77,15,NULL,1,'General Services Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-24 09:00:00','2026-07-20 14:59:08'),
(1017,'COA-2023-119','Road Roller',6,1,'2023-10-31',2920289.07,11,NULL,NULL,'Municipal Planning and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-03 09:00:00','2026-07-17 18:12:48'),
(1018,'COA-2019-099','Weighing Scale (Digital)',8,1,'2019-07-07',47020.99,1,'Antonio Santos',1,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-07-09 09:00:00','2026-07-20 14:59:08'),
(1019,'COA-2023-120','Typewriter (Manual)',4,1,'2023-12-25',25554.51,9,'Josefa Flores',1,'Civil Registrar\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-25 09:00:00','2026-07-20 14:59:08'),
(1020,'COA-2019-100','Grass Cutter (Riding Type)',6,1,'2019-07-10',2867158.48,16,'Divina Fernandez',NULL,'Information and Communications Technology Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-07-13 09:00:00','2026-07-20 14:59:08'),
(1021,'COA-2018-101','Sprayer (Backpack, Motorized)',9,2,'2018-10-13',127164.04,10,NULL,NULL,'Municipal Engineering Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2018-10-13 09:00:00','2026-07-20 14:59:08'),
(1022,'COA-2023-121','Steel Locker Cabinet',3,5,'2023-01-07',5407.02,15,'Antonio Bautista',5,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-10 09:00:00','2026-07-17 18:12:48'),
(1023,'COA-2016-097','Electric Kettle',1,1,'2016-08-02',31510.19,4,'Antonio Ocampo',1,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-03 09:00:00','2026-07-17 18:12:48'),
(1024,'COA-2019-101','Electric Fan (Stand Type)',1,1,'2019-08-20',48871.13,10,'Danilo Marquez',1,'Municipal Engineering Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-22 09:00:00','2026-07-20 14:59:08'),
(1025,'COA-2020-070','24-Port Network Switch',2,1,'2020-01-02',13330.38,12,'Jose Salazar',1,'Municipal Health Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-04 09:00:00','2026-07-17 18:12:48'),
(1026,'COA-2017-105','Paper Shredder (Heavy Duty)',4,1,'2017-10-13',50291.37,15,NULL,1,'General Services Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2017-10-13 09:00:00','2026-07-17 18:12:48'),
(1027,'COA-2021-095','Bookshelf (Wooden, 5-Tier)',3,1,'2021-08-12',11585.68,5,'Manuel Dela Cruz',1,'Budget Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2021-08-13 09:00:00','2026-07-20 12:47:01'),
(1028,'COA-2022-095','Bulletin Board (Cork, Framed)',4,1,'2022-07-14',3443.45,8,'Eduardo Aquino',NULL,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-15 09:00:00','2026-07-17 18:12:48'),
(1029,'COA-2022-096','Multi-Purpose Van',5,1,'2022-03-28',1344039.34,9,'Carlos Cruz',1,'Civil Registrar\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2022-03-31 09:00:00','2026-07-17 18:12:48'),
(1030,'COA-2017-106','Photocopier Machine (Multi-function)',4,1,'2017-04-06',27022.03,6,'Gloria Torres',1,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-09 09:00:00','2026-07-17 18:12:48'),
(1031,'COA-2021-096','Service Vehicle (Sedan)',5,1,'2021-03-14',1583702.66,12,'Romeo Ramos',1,'Municipal Health Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-14 09:00:00','2026-07-17 18:12:48'),
(1032,'COA-2021-097','PABX Telephone System',7,1,'2021-02-18',28077.05,11,'Josefa Salazar',1,'Municipal Planning and Development Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-20 09:00:00','2026-07-20 14:59:08'),
(1033,'COA-2022-097','Electric Fan (Stand Type)',1,1,'2022-12-11',47501.21,1,NULL,1,'Office of the Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-14 09:00:00','2026-07-17 18:12:48'),
(1034,'COA-2024-096','Laminating Machine',4,1,'2024-04-26',7718.17,14,'Juan Villanueva',NULL,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-28 09:00:00','2026-07-17 18:12:48'),
(1035,'COA-2026-053','Photocopier Machine (Multi-function)',4,1,'2026-04-23',57578.02,4,NULL,NULL,'Human Resource Management Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2026-04-24 09:00:00','2026-07-17 18:12:48'),
(1036,'COA-2019-102','Fire Extinguisher (10lbs)',10,1,'2019-01-11',67367.54,9,'Norma Marquez',NULL,'Civil Registrar\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-14 09:00:00','2026-07-17 18:12:48'),
(1037,'COA-2023-122','Refrigerator (2-Door)',1,1,'2023-05-13',52870.02,2,NULL,NULL,'Office of the Vice Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-16 09:00:00','2026-07-17 18:12:48'),
(1038,'COA-2023-123','Digital Blood Pressure Monitor',8,1,'2023-04-17',105012.22,1,'Teresa Gonzales',1,'Office of the Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-19 09:00:00','2026-07-17 18:12:48'),
(1039,'COA-2020-071','Nebulizer Machine',8,1,'2020-03-08',87554.53,6,'Antonio Ocampo',NULL,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-11 09:00:00','2026-07-17 18:12:48'),
(1040,'COA-2020-072','Autoclave Sterilizer',8,1,'2020-01-15',11743.80,14,'Pedro Castillo',NULL,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-15 09:00:00','2026-07-17 18:12:48'),
(1041,'COA-2022-098','Swivel Office Chair',3,5,'2022-01-21',4939.17,11,'Carlos Marquez',5,'Municipal Planning and Development Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-01-21 09:00:00','2026-07-17 18:12:48'),
(1042,'COA-2017-107','Electric Fan (Stand Type)',1,1,'2017-03-01',15872.65,17,'Rosa Ocampo',NULL,'Disaster Risk Reduction and Management Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-01 09:00:00','2026-07-20 14:59:08'),
(1043,'COA-2023-124','Megaphone (Bullhorn)',7,1,'2023-05-14',19193.99,17,'Norma Aguilar',NULL,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-15 09:00:00','2026-07-17 18:12:48'),
(1044,'COA-2021-098','Rice Thresher',9,1,'2021-07-21',126156.45,4,'Ernesto Domingo',1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2021-07-22 09:00:00','2026-07-20 14:59:08'),
(1045,'COA-2025-089','Paper Shredder (Heavy Duty)',4,1,'2025-04-13',7155.35,6,'Ana Aguilar',1,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-13 09:00:00','2026-07-17 18:12:48'),
(1046,'COA-2023-125','Chainsaw (Rescue Type)',10,1,'2023-02-14',57180.27,16,'Maria Salazar',NULL,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-17 09:00:00','2026-07-17 18:12:48'),
(1047,'COA-2023-126','PABX Telephone System',7,1,'2023-09-06',44772.13,12,'Josefa Santos',1,'Municipal Health Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2023-09-07 09:00:00','2026-07-17 18:12:48'),
(1048,'COA-2022-099','Water Tanker Truck',6,1,'2022-10-08',447875.13,8,'Ernesto Marquez',NULL,'Assessor\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-09 09:00:00','2026-07-20 14:59:08'),
(1049,'COA-2016-098','Seedling Tray Set',9,1,'2016-10-10',85251.27,15,'Manuel Gonzales',1,'General Services Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-10 09:00:00','2026-07-17 18:12:48'),
(1050,'COA-2022-100','Electric Kettle',1,1,'2022-09-28',24903.41,10,'Alfredo Santos',1,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-28 09:00:00','2026-07-17 18:12:48'),
(1051,'COA-2019-103','Base Radio Station',7,1,'2019-05-23',11995.46,2,NULL,NULL,'Office of the Vice Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-25 09:00:00','2026-07-17 18:12:48'),
(1052,'COA-2024-097','Executive Office Desk',3,2,'2024-04-20',14496.70,5,'Teresa Dela Cruz',2,'Budget Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-23 09:00:00','2026-07-20 12:47:01'),
(1053,'COA-2016-099','Handheld Two-Way Radio',7,1,'2016-09-23',13667.96,3,NULL,1,'Sangguniang Bayan Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2016-09-25 09:00:00','2026-07-17 18:12:48'),
(1054,'COA-2023-127','Rescue Rope Kit',10,1,'2023-06-15',43487.50,6,NULL,1,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-17 09:00:00','2026-07-20 14:59:08'),
(1055,'COA-2018-102','Water Dispenser (Hot & Cold)',1,1,'2018-04-09',18268.01,8,'Manuel Dela Cruz',1,'Assessor\'s Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-04-09 09:00:00','2026-07-17 18:12:48'),
(1056,'COA-2016-100','Life Vest',10,1,'2016-02-06',83875.77,17,'Gloria Flores',1,'Disaster Risk Reduction and Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-09 09:00:00','2026-07-17 18:12:48'),
(1057,'COA-2017-108','Farm Tool Kit',9,1,'2017-08-21',154909.75,3,'Ernesto Santos',NULL,'Sangguniang Bayan Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-22 09:00:00','2026-07-20 14:59:08'),
(1058,'COA-2025-090','Bulldozer',6,1,'2025-04-14',1508215.67,8,'Maria Castillo',1,'Assessor\'s Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-04-17 09:00:00','2026-07-17 18:12:48'),
(1059,'COA-2024-098','Rescue Rope Kit',10,1,'2024-05-24',46581.02,8,NULL,1,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-26 09:00:00','2026-07-17 18:12:48'),
(1060,'COA-2022-101','Desktop Computer Set (Core i5)',2,1,'2022-09-22',39550.68,14,'Danilo Garcia',NULL,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-22 09:00:00','2026-07-17 18:12:48'),
(1061,'COA-2026-054','Water Pump (Irrigation)',9,2,'2026-04-23',93769.15,11,'Leonora Marquez',2,'Municipal Planning and Development Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-26 09:00:00','2026-07-20 14:59:08'),
(1062,'COA-2019-104','UPS (Uninterruptible Power Supply)',2,1,'2019-11-03',47325.81,16,'Ramon Fernandez',NULL,'Information and Communications Technology Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-06 09:00:00','2026-07-20 14:59:08'),
(1063,'COA-2019-105','Binding Machine',4,1,'2019-11-28',14894.49,7,'Imelda Aguilar',NULL,'Treasury Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-01 09:00:00','2026-07-17 18:12:48'),
(1064,'COA-2023-128','Dump Truck',5,1,'2023-09-15',1082602.14,7,'Antonio Torres',1,'Treasury Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-17 09:00:00','2026-07-17 18:12:48'),
(1065,'COA-2025-091','Generator Set (25 kVA)',6,1,'2025-12-13',2657295.85,6,'Manuel Salazar',1,'Accounting Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-15 09:00:00','2026-07-17 18:12:48'),
(1066,'COA-2016-101','Handheld Two-Way Radio',7,1,'2016-01-14',10529.44,13,NULL,1,'Municipal Social Welfare and Development Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-14 09:00:00','2026-07-20 14:59:08'),
(1067,'COA-2023-129','Water Cooler/Dispenser',1,1,'2023-01-16',33751.77,14,'Manuel Castillo',1,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2023-01-19 09:00:00','2026-07-17 18:12:48'),
(1068,'COA-2017-109','Hand Tractor',9,2,'2017-06-05',39663.57,9,NULL,NULL,'Civil Registrar\'s Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-06-08 09:00:00','2026-07-17 18:12:48'),
(1069,'COA-2018-103','Service Pick-up Truck',5,1,'2018-09-12',835765.81,14,'Ernesto Ramos',NULL,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-15 09:00:00','2026-07-20 14:59:08'),
(1070,'COA-2022-102','CCTV Camera (Outdoor)',7,1,'2022-01-27',3241.22,7,'Eduardo Ocampo',NULL,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-30 09:00:00','2026-07-17 18:12:48'),
(1071,'COA-2026-055','Oxygen Tank with Regulator',8,1,'2026-01-01',110238.63,6,'Juan Flores',1,'Accounting Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-01 09:00:00','2026-07-20 14:59:08'),
(1072,'COA-2023-130','External Hard Drive 2TB',2,1,'2023-12-28',41517.15,14,'Manuel Cruz',1,'Municipal Agriculture Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-12-29 09:00:00','2026-07-17 18:12:48'),
(1073,'COA-2019-106','IP Desk Phone',7,1,'2019-11-03',3380.42,17,'Manuel Pascual',1,'Disaster Risk Reduction and Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-04 09:00:00','2026-07-20 14:59:08'),
(1074,'COA-2018-104','IP Desk Phone',7,1,'2018-06-11',17513.78,7,'Danilo Villanueva',1,'Treasury Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-12 09:00:00','2026-07-17 18:12:48'),
(1075,'COA-2023-131','Desktop Computer Set (Core i5)',2,1,'2023-12-30',37331.85,15,'Manuel Dela Cruz',1,'General Services Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-02 09:00:00','2026-07-17 18:12:48'),
(1076,'COA-2017-110','Service Pick-up Truck',5,1,'2017-10-09',833489.35,16,'Ricardo Cruz',NULL,'Information and Communications Technology Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2017-10-11 09:00:00','2026-07-17 18:12:48'),
(1077,'COA-2018-105','Laptop Computer (Business Series)',2,1,'2018-10-22',47969.80,2,'Pedro Villanueva',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-24 09:00:00','2026-07-20 14:59:08'),
(1078,'COA-2025-092','Laptop Computer (Business Series)',2,1,'2025-10-10',55433.68,8,'Divina Ocampo',1,'Assessor\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-12 09:00:00','2026-07-17 18:12:48'),
(1079,'COA-2016-102','Emergency Light Tower',10,1,'2016-10-02',11440.46,3,'Rosa Gonzales',1,'Sangguniang Bayan Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-02 09:00:00','2026-07-17 18:12:48'),
(1080,'COA-2025-093','Water Dispenser (Hot & Cold)',1,1,'2025-08-04',42733.36,11,'Juan Rivera',NULL,'Municipal Planning and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-06 09:00:00','2026-07-17 18:12:48'),
(1081,'COA-2022-103','Emergency Light Tower',10,1,'2022-06-08',27972.77,12,'Rosa Marquez',1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-09 09:00:00','2026-07-17 18:12:48'),
(1082,'COA-2023-132','Sprayer (Backpack, Motorized)',9,5,'2023-08-07',99069.27,16,'Ricardo Pascual',NULL,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-10 09:00:00','2026-07-17 18:12:48'),
(1083,'COA-2021-099','Megaphone (Bullhorn)',7,1,'2021-08-22',23738.38,6,'Carlos Santos',1,'Accounting Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-22 09:00:00','2026-07-20 14:59:08'),
(1084,'COA-2021-100','Air Conditioning Unit (1.5HP Split Type)',1,1,'2021-06-18',41891.35,11,'Ernesto Fernandez',NULL,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-20 09:00:00','2026-07-17 18:12:48'),
(1085,'COA-2026-056','Visitor\'s Chair (Stackable)',3,2,'2026-02-05',7978.25,1,'Danilo Pascual',NULL,'Office of the Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-06 09:00:00','2026-07-17 18:12:48'),
(1086,'COA-2016-103','Multi-Purpose Van',5,1,'2016-08-05',1263906.48,12,'Rodrigo Aguilar',NULL,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-07 09:00:00','2026-07-17 18:12:48'),
(1087,'COA-2019-107','Nebulizer Machine',8,1,'2019-12-14',24427.30,3,NULL,1,'Sangguniang Bayan Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-12-15 09:00:00','2026-07-17 18:12:48'),
(1088,'COA-2021-101','Air Conditioning Unit (1.5HP Split Type)',1,1,'2021-09-17',35610.41,1,'Francisco Domingo',1,'Office of the Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-19 09:00:00','2026-07-17 18:12:48'),
(1089,'COA-2024-099','External Hard Drive 2TB',2,1,'2024-07-03',40805.84,15,'Imelda Gonzales',1,'General Services Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-03 09:00:00','2026-07-20 14:59:08'),
(1090,'COA-2017-111','Patrol Motorcycle',5,1,'2017-08-05',2051240.93,5,'Manuel Ramos',1,'Budget Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-08 09:00:00','2026-07-20 14:59:08'),
(1091,'COA-2022-104','Conference Table (8-Seater)',3,1,'2022-02-18',1215.20,14,'Leonora Reyes',1,'Municipal Agriculture Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-19 09:00:00','2026-07-20 14:59:08'),
(1092,'COA-2023-133','External Hard Drive 2TB',2,1,'2023-07-04',70311.80,3,'Norma Aquino',NULL,'Sangguniang Bayan Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-07 09:00:00','2026-07-17 18:12:48'),
(1093,'COA-2017-112','Generator Set (25 kVA)',6,1,'2017-09-29',2293578.27,17,'Ricardo Del Rosario',1,'Disaster Risk Reduction and Management Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-30 09:00:00','2026-07-20 14:59:08'),
(1094,'COA-2021-102','Farm Tool Kit',9,2,'2021-08-05',12552.08,10,'Divina Ramos',NULL,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-05 09:00:00','2026-07-20 14:59:08'),
(1095,'COA-2023-134','Bookshelf (Wooden, 5-Tier)',3,2,'2023-10-27',21099.63,4,'Antonio Villanueva',NULL,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-30 09:00:00','2026-07-20 14:59:08'),
(1096,'COA-2020-073','Vacuum Cleaner',1,1,'2020-07-20',10587.41,14,'Juan Castillo',1,'Municipal Agriculture Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-23 09:00:00','2026-07-20 14:59:08'),
(1097,'COA-2019-108','Base Radio Station',7,1,'2019-03-19',28449.34,8,'Rosa Cruz',NULL,'Assessor\'s Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-22 09:00:00','2026-07-20 14:59:08'),
(1098,'COA-2026-057','Handheld Two-Way Radio',7,1,'2026-01-20',42210.91,16,'Danilo Fernandez',NULL,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-22 09:00:00','2026-07-17 18:12:48'),
(1099,'COA-2016-104','Road Roller',6,1,'2016-06-14',2894707.22,3,'Maria Navarro',NULL,'Sangguniang Bayan Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-16 09:00:00','2026-07-20 14:59:08'),
(1100,'COA-2018-106','Wheelchair',8,1,'2018-12-30',74429.06,4,'Alfredo Cruz',1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-31 09:00:00','2026-07-20 14:59:08'),
(1101,'COA-2022-105','All-in-One Inkjet Printer',2,1,'2022-10-20',60744.50,16,'Leonora Castillo',1,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-21 09:00:00','2026-07-20 14:59:08'),
(1102,'COA-2025-094','Base Radio Station',7,1,'2025-01-18',36255.94,14,'Imelda Castillo',1,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-19 09:00:00','2026-07-17 18:12:48'),
(1103,'COA-2024-100','Steel Filing Cabinet (4-Drawer)',3,1,'2024-02-08',21845.83,5,'Eduardo Flores',1,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-08 09:00:00','2026-07-20 12:47:01'),
(1104,'COA-2023-135','Photocopier Machine (Multi-function)',4,1,'2023-05-11',25580.98,16,'Carmen Santos',1,'Information and Communications Technology Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-05-12 09:00:00','2026-07-20 14:59:08'),
(1105,'COA-2023-136','Autoclave Sterilizer',8,1,'2023-05-20',94371.39,15,NULL,1,'General Services Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-22 09:00:00','2026-07-20 14:59:08'),
(1106,'COA-2016-105','Emergency Light Tower',10,1,'2016-01-31',74838.22,6,NULL,NULL,'Accounting Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-01 09:00:00','2026-07-17 18:12:48'),
(1107,'COA-2019-109','Rescue Rope Kit',10,1,'2019-02-12',69032.95,16,'Ernesto Dela Cruz',NULL,'Information and Communications Technology Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-12 09:00:00','2026-07-20 14:59:08'),
(1108,'COA-2017-113','Laminating Machine',4,1,'2017-08-28',45182.05,7,NULL,NULL,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-31 09:00:00','2026-07-17 18:12:48'),
(1109,'COA-2024-101','Microwave Oven',1,1,'2024-01-24',30786.59,15,'Maria Villanueva',1,'General Services Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-01-25 09:00:00','2026-07-17 18:12:48'),
(1110,'COA-2026-058','CCTV Camera (Outdoor)',7,1,'2026-04-02',26805.65,15,NULL,NULL,'General Services Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-02 09:00:00','2026-07-20 14:59:08'),
(1111,'COA-2020-074','Life Vest',10,1,'2020-06-05',2398.51,9,'Elena Pascual',1,'Civil Registrar\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-06-05 09:00:00','2026-07-20 14:59:08'),
(1112,'COA-2016-106','Seedling Tray Set',9,1,'2016-03-07',139211.00,14,'Josefa Navarro',NULL,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-08 09:00:00','2026-07-17 18:12:48'),
(1113,'COA-2022-106','Generator Set (25 kVA)',6,1,'2022-02-10',920732.67,6,'Jose Castillo',1,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-12 09:00:00','2026-07-20 14:59:08'),
(1114,'COA-2017-114','Ambulance Unit',5,1,'2017-10-24',807163.32,14,'Ana Villanueva',NULL,'Municipal Agriculture Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-27 09:00:00','2026-07-17 18:12:48'),
(1115,'COA-2016-107','Microwave Oven',1,1,'2016-09-27',53170.04,8,'Francisco Castillo',1,'Assessor\'s Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-28 09:00:00','2026-07-20 14:59:08'),
(1116,'COA-2024-102','Laptop Computer (Business Series)',2,1,'2024-11-05',34552.73,12,'Carlos Gonzales',NULL,'Municipal Health Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-05 09:00:00','2026-07-20 14:59:08'),
(1117,'COA-2019-110','Swivel Office Chair',3,5,'2019-11-02',23047.84,5,'Josefa Fernandez',5,'Budget Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-11-05 09:00:00','2026-07-20 14:59:08'),
(1118,'COA-2018-107','Rice Thresher',9,1,'2018-05-19',113119.75,13,'Eduardo Ocampo',1,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-21 09:00:00','2026-07-20 14:59:08'),
(1119,'COA-2018-108','Backhoe Loader',6,1,'2018-03-26',453681.52,12,'Eduardo Aquino',NULL,'Municipal Health Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-26 09:00:00','2026-07-20 14:59:08'),
(1120,'COA-2017-115','Weighing Scale (Digital)',8,1,'2017-07-03',71965.85,3,'Ana Navarro',1,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-03 09:00:00','2026-07-17 18:12:48'),
(1121,'COA-2019-111','Grass Cutter (Riding Type)',6,1,'2019-07-02',2693169.04,8,'Leonora Bautista',NULL,'Assessor\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-07-03 09:00:00','2026-07-20 14:59:08'),
(1122,'COA-2025-095','Ambulance Unit',5,1,'2025-07-12',2167292.96,11,NULL,1,'Municipal Planning and Development Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-07-14 09:00:00','2026-07-17 18:12:48'),
(1123,'COA-2018-109','Dump Truck',5,1,'2018-01-26',612883.44,11,'Ricardo Cruz',1,'Municipal Planning and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-27 09:00:00','2026-07-20 14:59:08'),
(1124,'COA-2022-107','Steel Filing Cabinet (4-Drawer)',3,1,'2022-07-12',2515.31,7,'Ernesto Gonzales',NULL,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-14 09:00:00','2026-07-17 18:12:48'),
(1125,'COA-2017-116','Sprayer (Backpack, Motorized)',9,1,'2017-02-15',58548.97,10,NULL,1,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-15 09:00:00','2026-07-20 14:59:08'),
(1126,'COA-2020-075','Weighing Scale (Digital)',8,1,'2020-07-20',32817.45,12,'Cecilia Flores',1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2020-07-21 09:00:00','2026-07-20 14:59:08'),
(1127,'COA-2024-103','Visitor\'s Chair (Stackable)',3,2,'2024-04-10',1341.68,6,'Ramon Navarro',2,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-11 09:00:00','2026-07-17 18:12:48'),
(1128,'COA-2017-117','Ambulance Unit',5,1,'2017-07-11',2154012.61,12,'Eduardo Villanueva',1,'Municipal Health Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-12 09:00:00','2026-07-20 14:59:08'),
(1129,'COA-2022-108','All-in-One Inkjet Printer',2,1,'2022-08-16',65249.28,13,'Eduardo Mendoza',1,'Municipal Social Welfare and Development Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-19 09:00:00','2026-07-20 14:59:08'),
(1130,'COA-2023-137','Vacuum Cleaner',1,1,'2023-09-02',9480.51,3,'Ana Navarro',1,'Sangguniang Bayan Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-02 09:00:00','2026-07-20 14:59:08'),
(1131,'COA-2017-118','Weighing Scale (Digital)',8,1,'2017-08-25',104452.94,5,'Teresa Domingo',1,'Budget Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-25 09:00:00','2026-07-20 12:47:01'),
(1132,'COA-2021-103','Binding Machine',4,1,'2021-06-25',30121.95,16,'Teresa Pascual',1,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-06-27 09:00:00','2026-07-20 14:59:08'),
(1133,'COA-2020-076','Service Vehicle (Sedan)',5,1,'2020-08-20',1992286.53,7,'Ramon Mendoza',1,'Treasury Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-22 09:00:00','2026-07-17 18:12:48'),
(1134,'COA-2023-138','Wheelchair',8,1,'2023-09-20',100976.95,7,NULL,NULL,'Treasury Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-21 09:00:00','2026-07-20 14:59:08'),
(1135,'COA-2022-109','CCTV Camera (Outdoor)',7,1,'2022-03-09',29780.26,8,'Ramon Ocampo',NULL,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-11 09:00:00','2026-07-17 18:12:48'),
(1136,'COA-2022-110','Refrigerator (2-Door)',1,1,'2022-05-12',15164.35,3,'Divina Flores',1,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-12 09:00:00','2026-07-20 14:59:08'),
(1137,'COA-2016-108','Electric Kettle',1,1,'2016-03-21',42845.89,5,'Teresa Navarro',1,'Budget Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-03-22 09:00:00','2026-07-20 12:47:01'),
(1138,'COA-2023-139','Megaphone (Bullhorn)',7,1,'2023-10-21',14057.52,9,'Manuel Del Rosario',NULL,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-23 09:00:00','2026-07-17 18:12:48'),
(1139,'COA-2021-104','Concrete Mixer',6,1,'2021-04-14',1037326.33,12,'Elena Aguilar',1,'Municipal Health Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-04-17 09:00:00','2026-07-17 18:12:48'),
(1140,'COA-2018-110','PABX Telephone System',7,1,'2018-04-19',20025.29,2,NULL,1,'Office of the Vice Mayor - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-20 09:00:00','2026-07-17 18:12:48'),
(1141,'COA-2016-109','Bulldozer',6,1,'2016-05-29',383338.81,4,'Ana Ramos',1,'Human Resource Management Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2016-05-31 09:00:00','2026-07-20 14:59:08'),
(1142,'COA-2016-110','Inflatable Rescue Boat',10,1,'2016-06-29',66076.69,8,'Imelda Marquez',NULL,'Assessor\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-30 09:00:00','2026-07-20 14:59:08'),
(1143,'COA-2022-111','Water Pump (Irrigation)',9,1,'2022-06-15',78884.16,8,'Carmen Pascual',1,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-15 09:00:00','2026-07-20 14:59:08'),
(1144,'COA-2018-111','Executive Office Desk',3,1,'2018-08-17',6448.94,6,'Pedro Villanueva',1,'Accounting Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-08-20 09:00:00','2026-07-17 18:12:48'),
(1145,'COA-2023-140','Binding Machine',4,1,'2023-01-12',54754.28,12,'Danilo Santos',1,'Municipal Health Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-12 09:00:00','2026-07-17 18:12:48'),
(1146,'COA-2024-104','Laser Printer (Monochrome)',2,1,'2024-07-28',23519.24,3,'Ana Aguilar',NULL,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-28 09:00:00','2026-07-17 18:12:48'),
(1147,'COA-2025-096','Inflatable Rescue Boat',10,1,'2025-12-09',16637.94,11,NULL,NULL,'Municipal Planning and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-12 09:00:00','2026-07-17 18:12:48'),
(1148,'COA-2022-112','Road Roller',6,1,'2022-10-19',2989707.37,9,'Alfredo Dela Cruz',NULL,'Civil Registrar\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-20 09:00:00','2026-07-17 18:12:48'),
(1149,'COA-2018-112','Steel Filing Cabinet (4-Drawer)',3,5,'2018-07-30',14045.82,2,NULL,NULL,'Office of the Vice Mayor - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-31 09:00:00','2026-07-20 14:59:08'),
(1150,'COA-2021-105','Paper Shredder (Heavy Duty)',4,1,'2021-09-13',17972.67,2,'Antonio Rivera',1,'Office of the Vice Mayor - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-15 09:00:00','2026-07-20 14:59:08'),
(1151,'COA-2025-097','Calculator (Desktop Printing)',4,1,'2025-01-01',46324.08,5,'Pedro Cruz',NULL,'Budget Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-01-03 09:00:00','2026-07-20 12:47:01'),
(1152,'COA-2017-119','Generator Set (25 kVA)',6,1,'2017-11-05',1137487.12,15,'Juan Reyes',NULL,'General Services Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2017-11-08 09:00:00','2026-07-20 14:59:08'),
(1153,'COA-2016-111','Metal Detector (Handheld)',10,1,'2016-12-04',19709.25,3,NULL,NULL,'Sangguniang Bayan Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-04 09:00:00','2026-07-20 14:59:08'),
(1154,'COA-2023-141','Backhoe Loader',6,1,'2023-07-16',2614865.26,13,'Luz Villanueva',1,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-18 09:00:00','2026-07-20 14:59:08'),
(1155,'COA-2017-120','Rice Thresher',9,1,'2017-09-08',91999.82,3,'Antonio Domingo',1,'Sangguniang Bayan Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-09-10 09:00:00','2026-07-17 18:12:48'),
(1156,'COA-2025-098','Air Conditioning Unit (1.5HP Split Type)',1,1,'2025-12-07',22339.53,9,'Jose Aquino',1,'Civil Registrar\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-08 09:00:00','2026-07-17 18:12:48'),
(1157,'COA-2019-112','Water Pump (Irrigation)',9,1,'2019-08-10',68136.18,8,'Divina Navarro',1,'Assessor\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-11 09:00:00','2026-07-20 14:59:08'),
(1158,'COA-2022-113','Life Vest',10,1,'2022-12-06',75146.66,15,'Corazon Fernandez',NULL,'General Services Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-07 09:00:00','2026-07-17 18:12:48'),
(1159,'COA-2025-099','Seedling Tray Set',9,5,'2025-12-25',133846.35,4,'Norma Ramos',5,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-27 09:00:00','2026-07-20 14:59:08'),
(1160,'COA-2023-142','Paper Shredder (Heavy Duty)',4,1,'2023-04-07',27781.94,17,'Imelda Santos',1,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-09 09:00:00','2026-07-17 18:12:48'),
(1161,'COA-2019-113','Service Pick-up Truck',5,1,'2019-05-03',486241.41,14,NULL,1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-03 09:00:00','2026-07-17 18:12:48'),
(1162,'COA-2025-100','Desktop Computer Set (Core i5)',2,1,'2025-10-17',71118.88,15,'Rodrigo Domingo',1,'General Services Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-20 09:00:00','2026-07-20 14:59:08'),
(1163,'COA-2019-114','Typewriter (Manual)',4,1,'2019-10-24',21217.65,12,NULL,NULL,'Municipal Health Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-27 09:00:00','2026-07-17 18:12:48'),
(1164,'COA-2026-059','Hand Tractor',9,1,'2026-04-11',132482.68,17,'Cecilia Marquez',1,'Disaster Risk Reduction and Management Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-12 09:00:00','2026-07-20 14:59:08'),
(1165,'COA-2016-112','Microwave Oven',1,1,'2016-06-02',38558.44,11,'Leonora Villanueva',1,'Municipal Planning and Development Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-03 09:00:00','2026-07-20 14:59:08'),
(1166,'COA-2025-101','Metal Detector (Handheld)',10,1,'2025-11-27',13362.78,11,'Divina Garcia',NULL,'Municipal Planning and Development Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-27 09:00:00','2026-07-17 18:12:48'),
(1167,'COA-2022-114','Rice Thresher',9,1,'2022-10-20',108220.57,2,'Carlos Salazar',NULL,'Office of the Vice Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-23 09:00:00','2026-07-20 14:59:08'),
(1168,'COA-2021-106','24-Port Network Switch',2,1,'2021-07-27',84330.91,17,'Ricardo Aguilar',1,'Disaster Risk Reduction and Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2021-07-28 09:00:00','2026-07-20 14:59:08'),
(1169,'COA-2019-115','Emergency Light Tower',10,1,'2019-10-02',40597.11,4,'Alfredo Cruz',NULL,'Human Resource Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-04 09:00:00','2026-07-17 18:12:48'),
(1170,'COA-2024-105','Ambulance Unit',5,1,'2024-02-16',2054176.21,4,NULL,1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-18 09:00:00','2026-07-17 18:12:48'),
(1171,'COA-2023-143','Document Scanner',2,1,'2023-03-03',29373.22,17,'Elena Flores',NULL,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-03 09:00:00','2026-07-20 14:59:08'),
(1172,'COA-2022-115','Swivel Office Chair',3,1,'2022-10-20',7635.82,7,'Antonio Aguilar',1,'Treasury Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-21 09:00:00','2026-07-17 18:12:48'),
(1173,'COA-2023-144','Electric Fan (Stand Type)',1,1,'2023-01-26',43345.97,12,'Josefa Domingo',1,'Municipal Health Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-28 09:00:00','2026-07-20 14:59:08'),
(1174,'COA-2018-113','Electric Fan (Stand Type)',1,1,'2018-03-01',29813.47,2,'Manuel Domingo',1,'Office of the Vice Mayor - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-03-03 09:00:00','2026-07-20 14:59:08'),
(1175,'COA-2019-116','Stretcher (Foldable)',8,1,'2019-08-05',13343.57,3,'Carlos Ramos',1,'Sangguniang Bayan Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-08 09:00:00','2026-07-20 14:59:08'),
(1176,'COA-2024-106','Oxygen Tank with Regulator',8,1,'2024-07-22',75109.67,14,NULL,1,'Municipal Agriculture Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-22 09:00:00','2026-07-20 14:59:08'),
(1177,'COA-2019-117','Wheelchair',8,1,'2019-11-04',29634.94,7,NULL,1,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-07 09:00:00','2026-07-17 18:12:48'),
(1178,'COA-2017-121','24-Port Network Switch',2,1,'2017-02-23',42219.64,2,'Corazon Reyes',1,'Office of the Vice Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-23 09:00:00','2026-07-17 18:12:48'),
(1179,'COA-2018-114','Water Dispenser (Hot & Cold)',1,1,'2018-11-11',23649.89,15,'Eduardo Cruz',1,'General Services Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-11 09:00:00','2026-07-17 18:12:48'),
(1180,'COA-2017-122','Chainsaw (Rescue Type)',10,1,'2017-01-02',29485.92,15,'Carmen Navarro',1,'General Services Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-05 09:00:00','2026-07-20 14:59:08'),
(1181,'COA-2017-123','Service Pick-up Truck',5,1,'2017-12-18',639621.02,7,'Divina Flores',NULL,'Treasury Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2017-12-19 09:00:00','2026-07-20 14:59:08'),
(1182,'COA-2017-124','Sprayer (Backpack, Motorized)',9,1,'2017-09-26',84192.53,16,'Romeo Dela Cruz',1,'Information and Communications Technology Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-28 09:00:00','2026-07-17 18:12:48'),
(1183,'COA-2023-145','Road Roller',6,1,'2023-04-17',2910787.41,12,'Imelda Gonzales',NULL,'Municipal Health Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-19 09:00:00','2026-07-20 14:59:08'),
(1184,'COA-2026-060','Document Scanner',2,1,'2026-02-12',54580.55,5,'Cecilia Garcia',1,'Budget Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-13 09:00:00','2026-07-20 12:47:01'),
(1185,'COA-2019-118','PABX Telephone System',7,1,'2019-11-12',29290.00,13,NULL,1,'Municipal Social Welfare and Development Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-11-12 09:00:00','2026-07-17 18:12:48'),
(1186,'COA-2025-102','Bookshelf (Wooden, 5-Tier)',3,5,'2025-01-19',10227.65,7,NULL,5,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-21 09:00:00','2026-07-17 18:12:48'),
(1187,'COA-2019-119','Dump Truck',5,1,'2019-01-18',2023239.33,17,NULL,1,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-20 09:00:00','2026-07-20 14:59:08'),
(1188,'COA-2016-113','Handheld Two-Way Radio',7,1,'2016-08-13',37932.69,3,'Ricardo Torres',NULL,'Sangguniang Bayan Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-08-14 09:00:00','2026-07-17 18:12:48'),
(1189,'COA-2016-114','Vacuum Cleaner',1,1,'2016-09-28',30210.15,2,'Ramon Santos',NULL,'Office of the Vice Mayor - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-01 09:00:00','2026-07-17 18:12:48'),
(1190,'COA-2025-103','Seedling Tray Set',9,2,'2025-10-11',116825.92,7,'Maria Ocampo',2,'Treasury Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-13 09:00:00','2026-07-20 14:59:08'),
(1191,'COA-2024-107','Partition Divider Panel',3,1,'2024-01-04',20657.37,2,'Teresa Del Rosario',NULL,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-04 09:00:00','2026-07-17 18:12:48'),
(1192,'COA-2016-115','Oxygen Tank with Regulator',8,1,'2016-07-14',68502.43,13,NULL,1,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2016-07-15 09:00:00','2026-07-17 18:12:48'),
(1193,'COA-2021-107','Calculator (Desktop Printing)',4,1,'2021-02-02',8529.58,7,'Gloria Castillo',1,'Treasury Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-03 09:00:00','2026-07-17 18:12:48'),
(1194,'COA-2016-116','All-in-One Inkjet Printer',2,1,'2016-02-13',73264.55,15,NULL,1,'General Services Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-16 09:00:00','2026-07-17 18:12:48'),
(1195,'COA-2017-125','Sprayer (Backpack, Motorized)',9,2,'2017-06-26',99888.91,11,NULL,2,'Municipal Planning and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-26 09:00:00','2026-07-20 14:59:08'),
(1196,'COA-2025-104','Electric Kettle',1,1,'2025-09-11',5008.75,6,NULL,NULL,'Accounting Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-12 09:00:00','2026-07-20 14:59:08'),
(1197,'COA-2025-105','Paper Shredder (Heavy Duty)',4,1,'2025-04-30',27698.29,9,'Gloria Garcia',1,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-03 09:00:00','2026-07-17 18:12:48'),
(1198,'COA-2026-061','Document Scanner',2,1,'2026-01-10',48827.03,16,'Rodrigo Torres',NULL,'Information and Communications Technology Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-13 09:00:00','2026-07-20 14:59:08'),
(1199,'COA-2018-115','Emergency Light Tower',10,1,'2018-08-15',41619.91,15,'Leonora Gonzales',1,'General Services Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-08-17 09:00:00','2026-07-20 14:59:08'),
(1200,'COA-2024-108','Fire Extinguisher (10lbs)',10,1,'2024-04-14',47832.83,15,'Cecilia Ocampo',1,'General Services Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-17 09:00:00','2026-07-20 14:59:08'),
(1201,'COA-2026-062','Autoclave Sterilizer',8,1,'2026-02-04',62915.87,8,'Leonora Dela Cruz',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-04 09:00:00','2026-07-20 14:59:08'),
(1202,'COA-2023-146','Road Roller',6,1,'2023-07-23',595639.02,11,'Leonora Del Rosario',NULL,'Municipal Planning and Development Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-07-26 09:00:00','2026-07-17 18:12:48'),
(1203,'COA-2022-116','Service Pick-up Truck',5,1,'2022-05-21',1731856.88,13,'Ernesto Mendoza',NULL,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-21 09:00:00','2026-07-17 18:12:48'),
(1204,'COA-2018-116','Sprayer (Backpack, Motorized)',9,5,'2018-08-21',110981.66,9,'Cecilia Dela Cruz',NULL,'Civil Registrar\'s Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-24 09:00:00','2026-07-20 14:59:08'),
(1205,'COA-2024-109','Binding Machine',4,1,'2024-01-24',34456.40,14,'Pedro Villanueva',1,'Municipal Agriculture Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-24 09:00:00','2026-07-17 18:12:48'),
(1206,'COA-2021-108','Digital Blood Pressure Monitor',8,1,'2021-02-18',83890.72,17,'Carmen Mendoza',NULL,'Disaster Risk Reduction and Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-20 09:00:00','2026-07-17 18:12:48'),
(1207,'COA-2019-120','Vacuum Cleaner',1,1,'2019-01-30',43463.02,15,NULL,1,'General Services Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-01 09:00:00','2026-07-17 18:12:48'),
(1208,'COA-2021-109','Inflatable Rescue Boat',10,1,'2021-09-02',68824.20,14,'Alfredo Garcia',1,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2021-09-03 09:00:00','2026-07-20 14:59:08'),
(1209,'COA-2016-117','Binding Machine',4,1,'2016-07-31',57747.27,12,'Leonora Aquino',1,'Municipal Health Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-01 09:00:00','2026-07-17 18:12:48'),
(1210,'COA-2024-110','Dump Truck',5,1,'2024-09-23',1049605.10,6,'Ramon Mendoza',NULL,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-26 09:00:00','2026-07-17 18:12:48'),
(1211,'COA-2023-147','Binding Machine',4,1,'2023-08-31',51951.18,5,'Elena Torres',1,'Budget Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2023-08-31 09:00:00','2026-07-20 12:47:01'),
(1212,'COA-2024-111','Partition Divider Panel',3,1,'2024-02-07',25693.96,11,'Rosa Navarro',1,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-10 09:00:00','2026-07-20 14:59:08'),
(1213,'COA-2018-117','Concrete Mixer',6,1,'2018-07-04',3175573.44,4,'Cecilia Marquez',NULL,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-05 09:00:00','2026-07-17 18:12:48'),
(1214,'COA-2016-118','Seedling Tray Set',9,1,'2016-03-05',136931.86,11,'Luz Ramos',NULL,'Municipal Planning and Development Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-03-08 09:00:00','2026-07-17 18:12:48'),
(1215,'COA-2025-106','Hand Tractor',9,2,'2025-05-02',109223.68,3,'Carlos Rivera',2,'Sangguniang Bayan Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-05 09:00:00','2026-07-20 14:59:08'),
(1216,'COA-2021-110','Backhoe Loader',6,1,'2021-02-01',1281288.32,10,'Ana Torres',NULL,'Municipal Engineering Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-02-01 09:00:00','2026-07-20 14:59:08'),
(1217,'COA-2024-112','LCD/LED Monitor 24\"',2,1,'2024-12-15',41891.50,8,'Juan Cruz',1,'Assessor\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-12-16 09:00:00','2026-07-20 14:59:08'),
(1218,'COA-2024-113','24-Port Network Switch',2,1,'2024-09-14',20831.33,2,'Ricardo Bautista',NULL,'Office of the Vice Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2024-09-17 09:00:00','2026-07-17 18:12:48'),
(1219,'COA-2025-107','Bookshelf (Wooden, 5-Tier)',3,2,'2025-06-21',5562.76,8,'Antonio Gonzales',NULL,'Assessor\'s Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-06-23 09:00:00','2026-07-20 14:59:08'),
(1220,'COA-2019-121','Oxygen Tank with Regulator',8,1,'2019-05-08',17878.96,9,'Ricardo Castillo',NULL,'Civil Registrar\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-11 09:00:00','2026-07-17 18:12:48'),
(1221,'COA-2017-126','Chainsaw (Rescue Type)',10,1,'2017-12-29',13987.41,10,NULL,1,'Municipal Engineering Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-29 09:00:00','2026-07-20 14:59:08'),
(1222,'COA-2017-127','Microwave Oven',1,1,'2017-09-30',22056.44,2,'Rodrigo Flores',NULL,'Office of the Vice Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-03 09:00:00','2026-07-20 14:59:08'),
(1223,'COA-2016-119','24-Port Network Switch',2,1,'2016-01-23',33514.52,7,'Carlos Fernandez',NULL,'Treasury Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-25 09:00:00','2026-07-20 14:59:08'),
(1224,'COA-2022-117','CCTV Camera (Outdoor)',7,1,'2022-07-30',44791.77,13,'Josefa Marquez',1,'Municipal Social Welfare and Development Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-31 09:00:00','2026-07-20 14:59:08'),
(1225,'COA-2020-077','Water Dispenser (Hot & Cold)',1,1,'2020-02-09',50760.16,5,'Jose Rivera',NULL,'Budget Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-09 09:00:00','2026-07-20 12:47:01'),
(1226,'COA-2018-118','Document Scanner',2,1,'2018-03-30',18170.58,5,'Juan Fernandez',1,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-31 09:00:00','2026-07-20 12:47:01'),
(1227,'COA-2018-119','Thermal Scanner',8,1,'2018-04-15',42383.34,6,'Ernesto Salazar',NULL,'Accounting Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-15 09:00:00','2026-07-17 18:12:48'),
(1228,'COA-2024-114','Bulldozer',6,1,'2024-05-17',1951817.71,9,'Pedro Domingo',1,'Civil Registrar\'s Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-20 09:00:00','2026-07-20 14:59:08'),
(1229,'COA-2026-063','Stretcher (Foldable)',8,1,'2026-02-01',87952.42,13,'Cecilia Mendoza',1,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-03 09:00:00','2026-07-17 18:12:48'),
(1230,'COA-2025-108','Photocopier Machine (Multi-function)',4,1,'2025-05-24',23201.00,6,'Eduardo Navarro',1,'Accounting Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-24 09:00:00','2026-07-17 18:12:48'),
(1231,'COA-2023-148','Life Vest',10,1,'2023-03-07',23973.30,3,'Elena Mendoza',NULL,'Sangguniang Bayan Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-10 09:00:00','2026-07-17 18:12:48'),
(1232,'COA-2018-120','Sprayer (Backpack, Motorized)',9,1,'2018-12-28',89826.72,10,'Norma Ocampo',1,'Municipal Engineering Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-31 09:00:00','2026-07-20 14:59:08'),
(1233,'COA-2022-118','Dump Truck',5,1,'2022-11-08',1718802.11,16,'Francisco Cruz',1,'Information and Communications Technology Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-09 09:00:00','2026-07-17 18:12:48'),
(1234,'COA-2024-115','Chainsaw (Rescue Type)',10,1,'2024-07-08',86691.70,15,'Carlos Salazar',1,'General Services Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2024-07-11 09:00:00','2026-07-20 14:59:08'),
(1235,'COA-2020-078','Executive Office Desk',3,5,'2020-06-14',6250.20,12,'Maria Ramos',5,'Municipal Health Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-06-17 09:00:00','2026-07-20 14:59:08'),
(1236,'COA-2023-149','Stretcher (Foldable)',8,1,'2023-09-01',83658.37,12,'Romeo Aquino',NULL,'Municipal Health Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-02 09:00:00','2026-07-17 18:12:48'),
(1237,'COA-2016-120','Microwave Oven',1,1,'2016-03-12',53844.47,7,'Manuel Fernandez',1,'Treasury Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-12 09:00:00','2026-07-20 14:59:08'),
(1238,'COA-2025-109','Steel Filing Cabinet (4-Drawer)',3,1,'2025-10-11',22075.72,7,'Rosa Ocampo',1,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-13 09:00:00','2026-07-20 14:59:08'),
(1239,'COA-2016-121','Seedling Tray Set',9,1,'2016-08-20',164407.01,7,'Josefa Santos',1,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-20 09:00:00','2026-07-17 18:12:48'),
(1240,'COA-2018-121','Swivel Office Chair',3,1,'2018-04-28',24428.39,4,NULL,NULL,'Human Resource Management Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-01 09:00:00','2026-07-20 14:59:08'),
(1241,'COA-2020-079','LCD/LED Monitor 24\"',2,1,'2020-04-16',15151.43,4,NULL,1,'Human Resource Management Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-17 09:00:00','2026-07-17 18:12:48'),
(1242,'COA-2018-122','Stretcher (Foldable)',8,1,'2018-03-21',5887.23,8,'Teresa Domingo',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-22 09:00:00','2026-07-17 18:12:48'),
(1243,'COA-2017-128','Water Pump (Irrigation)',9,1,'2017-09-04',21230.96,4,'Divina Gonzales',NULL,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-04 09:00:00','2026-07-17 18:12:48'),
(1244,'COA-2017-129','Service Vehicle (Sedan)',5,1,'2017-06-11',1919984.92,13,'Danilo Aquino',1,'Municipal Social Welfare and Development Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-11 09:00:00','2026-07-20 14:59:08'),
(1245,'COA-2017-130','Bulletin Board (Cork, Framed)',4,1,'2017-06-09',54056.61,12,'Elena Pascual',1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-12 09:00:00','2026-07-20 14:59:08'),
(1246,'COA-2025-110','Executive Office Desk',3,1,'2025-06-28',26432.54,7,NULL,1,'Treasury Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-07-01 09:00:00','2026-07-20 14:59:08'),
(1247,'COA-2021-111','Road Roller',6,1,'2021-05-17',1938955.95,6,'Rosa Cruz',1,'Accounting Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-05-20 09:00:00','2026-07-17 18:12:48'),
(1248,'COA-2020-080','Rescue Rope Kit',10,1,'2020-08-15',14088.85,1,NULL,NULL,'Office of the Mayor - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-17 09:00:00','2026-07-20 14:59:08'),
(1249,'COA-2023-150','Microwave Oven',1,1,'2023-11-12',4200.11,8,'Juan Cruz',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-15 09:00:00','2026-07-17 18:12:48'),
(1250,'COA-2020-081','Ambulance Unit',5,1,'2020-02-28',1482715.07,3,'Carmen Aquino',1,'Sangguniang Bayan Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-01 09:00:00','2026-07-17 18:12:48'),
(1251,'COA-2020-082','Service Vehicle (Sedan)',5,1,'2020-11-13',643480.40,15,'Ernesto Bautista',1,'General Services Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-16 09:00:00','2026-07-20 14:59:08'),
(1252,'COA-2024-116','Handheld Two-Way Radio',7,1,'2024-07-24',23281.83,9,'Maria Gonzales',1,'Civil Registrar\'s Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2024-07-26 09:00:00','2026-07-20 14:59:08'),
(1253,'COA-2021-112','Backhoe Loader',6,1,'2021-03-13',907134.39,2,'Francisco Bautista',NULL,'Office of the Vice Mayor - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-03-13 09:00:00','2026-07-17 18:12:48'),
(1254,'COA-2021-113','Multi-Purpose Van',5,1,'2021-12-13',1311057.97,12,'Manuel Mendoza',1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-13 09:00:00','2026-07-17 18:12:48'),
(1255,'COA-2020-083','Generator Set (25 kVA)',6,1,'2020-10-10',1574032.01,15,'Juan Torres',NULL,'General Services Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-11 09:00:00','2026-07-20 14:59:08'),
(1256,'COA-2018-123','Steel Locker Cabinet',3,2,'2018-11-07',12906.48,15,'Carmen Navarro',2,'General Services Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-09 09:00:00','2026-07-20 14:59:08'),
(1257,'COA-2020-084','Handheld Two-Way Radio',7,1,'2020-10-09',15700.55,14,'Eduardo Dela Cruz',1,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-11 09:00:00','2026-07-17 18:12:48'),
(1258,'COA-2022-119','Air Conditioning Unit (1.5HP Split Type)',1,1,'2022-07-26',31053.59,9,NULL,1,'Civil Registrar\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-27 09:00:00','2026-07-17 18:12:48'),
(1259,'COA-2023-151','Generator Set (25 kVA)',6,1,'2023-06-27',537469.65,8,'Maria Ramos',1,'Assessor\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-27 09:00:00','2026-07-17 18:12:48'),
(1260,'COA-2021-114','CCTV DVR/NVR Unit',7,1,'2021-07-11',12006.43,17,'Francisco Navarro',1,'Disaster Risk Reduction and Management Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-14 09:00:00','2026-07-20 14:59:08'),
(1261,'COA-2017-131','Base Radio Station',7,1,'2017-08-31',23110.61,4,NULL,1,'Human Resource Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-02 09:00:00','2026-07-17 18:12:48'),
(1262,'COA-2022-120','Seedling Tray Set',9,1,'2022-07-15',179235.86,10,'Juan Santos',1,'Municipal Engineering Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-17 09:00:00','2026-07-20 14:59:08'),
(1263,'COA-2025-111','Seedling Tray Set',9,1,'2025-03-11',22154.49,15,'Alfredo Mendoza',NULL,'General Services Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-11 09:00:00','2026-07-17 18:12:48'),
(1264,'COA-2020-085','Document Scanner',2,1,'2020-02-21',51581.87,8,'Romeo Navarro',1,'Assessor\'s Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-23 09:00:00','2026-07-20 14:59:08'),
(1265,'COA-2023-152','Seedling Tray Set',9,1,'2023-06-02',147403.78,10,NULL,NULL,'Municipal Engineering Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-05 09:00:00','2026-07-20 14:59:08'),
(1266,'COA-2021-115','Generator Set (25 kVA)',6,1,'2021-10-02',2992241.53,17,'Francisco Rivera',1,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2021-10-02 09:00:00','2026-07-17 18:12:48'),
(1267,'COA-2023-153','Backhoe Loader',6,1,'2023-06-23',2712110.32,16,'Carlos Domingo',1,'Information and Communications Technology Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-06-26 09:00:00','2026-07-17 18:12:48'),
(1268,'COA-2021-116','External Hard Drive 2TB',2,1,'2021-09-23',59598.56,6,'Divina Mendoza',NULL,'Accounting Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-23 09:00:00','2026-07-17 18:12:48'),
(1269,'COA-2018-124','Digital Blood Pressure Monitor',8,1,'2018-12-30',71277.74,2,'Ana Ramos',1,'Office of the Vice Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-01 09:00:00','2026-07-17 18:12:48'),
(1270,'COA-2019-122','Farm Tool Kit',9,2,'2019-09-27',65988.52,8,'Francisco Navarro',NULL,'Assessor\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-28 09:00:00','2026-07-20 14:59:08'),
(1271,'COA-2020-086','Chainsaw (Rescue Type)',10,1,'2020-04-20',25124.91,13,'Corazon Aguilar',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-22 09:00:00','2026-07-17 18:12:48'),
(1272,'COA-2017-132','IP Desk Phone',7,1,'2017-10-16',27149.89,5,'Rodrigo Aguilar',NULL,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-16 09:00:00','2026-07-20 12:47:01'),
(1273,'COA-2021-117','Farm Tool Kit',9,5,'2021-12-21',43733.54,13,'Teresa Garcia',5,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2021-12-22 09:00:00','2026-07-20 14:59:08'),
(1274,'COA-2016-122','Life Vest',10,1,'2016-12-31',8868.33,3,NULL,NULL,'Sangguniang Bayan Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-03 09:00:00','2026-07-20 14:59:08'),
(1275,'COA-2024-117','Steel Locker Cabinet',3,1,'2024-01-06',7434.99,7,'Teresa Dela Cruz',1,'Treasury Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2024-01-07 09:00:00','2026-07-20 14:59:08'),
(1276,'COA-2020-087','Microwave Oven',1,1,'2020-01-15',41900.01,6,'Ramon Bautista',1,'Accounting Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-18 09:00:00','2026-07-20 14:59:08'),
(1277,'COA-2020-088','Emergency Light Tower',10,1,'2020-07-04',7875.70,14,'Josefa Ocampo',NULL,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-07 09:00:00','2026-07-17 18:12:48'),
(1278,'COA-2025-112','Sprayer (Backpack, Motorized)',9,2,'2025-09-18',150582.38,1,'Ramon Santos',NULL,'Office of the Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-20 09:00:00','2026-07-20 14:59:08'),
(1279,'COA-2018-125','CCTV Camera (Outdoor)',7,1,'2018-12-21',20442.87,13,'Corazon Flores',1,'Municipal Social Welfare and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-23 09:00:00','2026-07-17 18:12:48'),
(1280,'COA-2019-123','Document Scanner',2,1,'2019-10-25',27375.07,11,'Imelda Reyes',NULL,'Municipal Planning and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-27 09:00:00','2026-07-17 18:12:48'),
(1281,'COA-2023-154','Water Tanker Truck',6,1,'2023-10-25',2884088.39,8,'Ana Santos',NULL,'Assessor\'s Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-10-28 09:00:00','2026-07-17 18:12:48'),
(1282,'COA-2018-126','Sprayer (Backpack, Motorized)',9,1,'2018-04-28',47369.58,13,NULL,1,'Municipal Social Welfare and Development Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-01 09:00:00','2026-07-20 14:59:08'),
(1283,'COA-2022-121','Microwave Oven',1,1,'2022-08-30',44867.16,1,'Eduardo Ramos',1,'Office of the Mayor - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-08-30 09:00:00','2026-07-20 14:59:08'),
(1284,'COA-2020-089','Ambulance Unit',5,1,'2020-11-01',1168305.53,14,'Teresa Ramos',1,'Municipal Agriculture Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-11-03 09:00:00','2026-07-17 18:12:48'),
(1285,'COA-2024-118','Water Tanker Truck',6,1,'2024-06-24',1318762.71,16,NULL,1,'Information and Communications Technology Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-24 09:00:00','2026-07-20 14:59:08'),
(1286,'COA-2020-090','Rescue Rope Kit',10,1,'2020-10-07',24554.05,1,'Ramon Domingo',NULL,'Office of the Mayor - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2020-10-09 09:00:00','2026-07-20 14:59:08'),
(1287,'COA-2018-127','Backhoe Loader',6,1,'2018-07-26',376094.88,12,NULL,NULL,'Municipal Health Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-27 09:00:00','2026-07-17 18:12:48'),
(1288,'COA-2023-155','CCTV DVR/NVR Unit',7,1,'2023-10-13',22642.81,16,'Ernesto Castillo',1,'Information and Communications Technology Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-10-15 09:00:00','2026-07-17 18:12:48'),
(1289,'COA-2020-091','UPS (Uninterruptible Power Supply)',2,1,'2020-03-05',70592.27,3,'Divina Rivera',1,'Sangguniang Bayan Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-05 09:00:00','2026-07-20 14:59:08'),
(1290,'COA-2023-156','PABX Telephone System',7,1,'2023-12-22',44644.57,16,'Leonora Santos',NULL,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-24 09:00:00','2026-07-20 14:59:08'),
(1291,'COA-2017-133','Dump Truck',5,1,'2017-07-06',1164960.19,15,'Rosa Fernandez',1,'General Services Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-07-09 09:00:00','2026-07-17 18:12:48'),
(1292,'COA-2018-128','Farm Tool Kit',9,2,'2018-07-26',63889.53,9,'Danilo Navarro',NULL,'Civil Registrar\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-27 09:00:00','2026-07-17 18:12:48'),
(1293,'COA-2017-134','Multi-Purpose Van',5,1,'2017-12-17',673854.23,17,'Danilo Flores',1,'Disaster Risk Reduction and Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2017-12-20 09:00:00','2026-07-17 18:12:48'),
(1294,'COA-2023-157','Multi-Purpose Van',5,1,'2023-04-27',949112.16,10,'Norma Garcia',NULL,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-27 09:00:00','2026-07-20 14:59:08'),
(1295,'COA-2023-158','Motorcycle (Service Unit)',5,1,'2023-08-26',1733519.71,16,NULL,1,'Information and Communications Technology Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-27 09:00:00','2026-07-20 14:59:08'),
(1296,'COA-2017-135','Executive Office Desk',3,1,'2017-11-26',24451.94,16,'Manuel Del Rosario',NULL,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2017-11-28 09:00:00','2026-07-20 14:59:08'),
(1297,'COA-2018-129','Laminating Machine',4,1,'2018-11-10',47315.01,2,'Manuel Cruz',1,'Office of the Vice Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-12 09:00:00','2026-07-20 14:59:08'),
(1298,'COA-2016-123','Photocopier Machine (Multi-function)',4,1,'2016-02-18',56185.99,10,NULL,1,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-19 09:00:00','2026-07-17 18:12:48'),
(1299,'COA-2017-136','IP Desk Phone',7,1,'2017-12-06',13299.36,12,NULL,NULL,'Municipal Health Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-07 09:00:00','2026-07-20 14:59:08'),
(1300,'COA-2022-122','Document Scanner',2,1,'2022-10-04',23960.53,16,'Cecilia Bautista',1,'Information and Communications Technology Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-05 09:00:00','2026-07-20 14:59:08'),
(1301,'COA-2021-118','Conference Table (8-Seater)',3,5,'2021-08-19',20907.14,15,'Eduardo Navarro',NULL,'General Services Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-19 09:00:00','2026-07-17 18:12:48'),
(1302,'COA-2021-119','Motorcycle (Service Unit)',5,1,'2021-05-25',1680385.75,11,'Ana Ramos',NULL,'Municipal Planning and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-26 09:00:00','2026-07-17 18:12:48'),
(1303,'COA-2023-159','Water Pump (Irrigation)',9,1,'2023-12-20',50766.63,13,NULL,1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-21 09:00:00','2026-07-17 18:12:48'),
(1304,'COA-2016-124','LCD/LED Monitor 24\"',2,1,'2016-05-03',78756.15,16,'Romeo Navarro',1,'Information and Communications Technology Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-05-06 09:00:00','2026-07-17 18:12:48'),
(1305,'COA-2018-130','All-in-One Inkjet Printer',2,1,'2018-01-28',20706.87,1,'Jose Marquez',1,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-31 09:00:00','2026-07-20 14:59:08'),
(1306,'COA-2024-119','Sprayer (Backpack, Motorized)',9,1,'2024-01-07',5477.52,16,'Luz Torres',NULL,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-08 09:00:00','2026-07-20 14:59:08'),
(1307,'COA-2023-160','Backhoe Loader',6,1,'2023-03-11',2030453.01,8,'Divina Salazar',1,'Assessor\'s Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-13 09:00:00','2026-07-20 14:59:08'),
(1308,'COA-2025-113','Metal Detector (Handheld)',10,1,'2025-05-01',75479.81,11,'Carlos Ocampo',1,'Municipal Planning and Development Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-02 09:00:00','2026-07-20 14:59:08'),
(1309,'COA-2020-092','Concrete Mixer',6,1,'2020-11-27',562418.70,13,'Danilo Reyes',1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-29 09:00:00','2026-07-20 14:59:08'),
(1310,'COA-2019-124','Megaphone (Bullhorn)',7,1,'2019-05-10',6178.02,12,'Alfredo Flores',1,'Municipal Health Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-05-12 09:00:00','2026-07-17 18:12:48'),
(1311,'COA-2024-120','Chainsaw (Rescue Type)',10,1,'2024-08-29',45657.34,9,'Juan Aquino',1,'Civil Registrar\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-29 09:00:00','2026-07-17 18:12:48'),
(1312,'COA-2017-137','Inflatable Rescue Boat',10,1,'2017-10-14',58444.79,13,'Ricardo Flores',1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-17 09:00:00','2026-07-20 14:59:08'),
(1313,'COA-2020-093','Digital Blood Pressure Monitor',8,1,'2020-01-31',45463.00,3,'Rosa Aquino',1,'Sangguniang Bayan Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-03 09:00:00','2026-07-20 14:59:08'),
(1314,'COA-2017-138','Vacuum Cleaner',1,1,'2017-06-27',48761.93,3,'Carmen Pascual',1,'Sangguniang Bayan Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2017-06-30 09:00:00','2026-07-20 14:59:08'),
(1315,'COA-2024-121','Partition Divider Panel',3,1,'2024-10-16',10194.47,3,'Ana Pascual',1,'Sangguniang Bayan Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-17 09:00:00','2026-07-17 18:12:48'),
(1316,'COA-2022-123','UPS (Uninterruptible Power Supply)',2,1,'2022-01-28',18282.97,4,'Danilo Navarro',NULL,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-30 09:00:00','2026-07-17 18:12:48'),
(1317,'COA-2021-120','Fire Extinguisher (10lbs)',10,1,'2021-01-14',77438.14,3,NULL,NULL,'Sangguniang Bayan Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-17 09:00:00','2026-07-20 14:59:08'),
(1318,'COA-2021-121','Patrol Motorcycle',5,1,'2021-06-14',1911264.57,12,'Ernesto Rivera',NULL,'Municipal Health Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-06-15 09:00:00','2026-07-17 18:12:48'),
(1319,'COA-2023-161','Digital Blood Pressure Monitor',8,1,'2023-12-19',112664.49,1,'Rodrigo Domingo',1,'Office of the Mayor - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-20 09:00:00','2026-07-20 14:59:08'),
(1320,'COA-2025-114','Partition Divider Panel',3,1,'2025-07-03',14683.04,9,NULL,1,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-05 09:00:00','2026-07-17 18:12:48'),
(1321,'COA-2017-139','Farm Tool Kit',9,1,'2017-10-21',130064.05,6,'Pedro Aguilar',1,'Accounting Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-23 09:00:00','2026-07-17 18:12:48'),
(1322,'COA-2022-124','Electric Fan (Stand Type)',1,1,'2022-04-22',7302.01,12,'Juan Cruz',1,'Municipal Health Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-04-23 09:00:00','2026-07-20 14:59:08'),
(1323,'COA-2024-122','24-Port Network Switch',2,1,'2024-05-04',24738.20,2,'Divina Pascual',NULL,'Office of the Vice Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-07 09:00:00','2026-07-20 14:59:08'),
(1324,'COA-2021-122','Microwave Oven',1,1,'2021-06-04',50067.68,1,'Rodrigo Santos',1,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-07 09:00:00','2026-07-17 18:12:48'),
(1325,'COA-2021-123','Inflatable Rescue Boat',10,1,'2021-04-02',57158.12,17,'Leonora Aguilar',1,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-03 09:00:00','2026-07-20 14:59:08'),
(1326,'COA-2017-140','Inflatable Rescue Boat',10,1,'2017-08-01',20803.17,17,'Cecilia Santos',1,'Disaster Risk Reduction and Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-04 09:00:00','2026-07-20 14:59:08'),
(1327,'COA-2018-131','Farm Tool Kit',9,1,'2018-06-27',15629.21,13,NULL,1,'Municipal Social Welfare and Development Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-30 09:00:00','2026-07-20 14:59:08'),
(1328,'COA-2025-115','Typewriter (Manual)',4,1,'2025-10-09',29081.97,11,'Leonora Ramos',1,'Municipal Planning and Development Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-10 09:00:00','2026-07-20 14:59:08'),
(1329,'COA-2022-125','Motorcycle (Service Unit)',5,1,'2022-01-28',791655.88,10,'Rosa Castillo',1,'Municipal Engineering Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-31 09:00:00','2026-07-20 14:59:08'),
(1330,'COA-2019-125','Electric Fan (Stand Type)',1,1,'2019-09-30',25889.59,11,'Ramon Marquez',NULL,'Municipal Planning and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-30 09:00:00','2026-07-17 18:12:48'),
(1331,'COA-2024-123','Emergency Light Tower',10,1,'2024-03-05',2905.18,6,'Gloria Castillo',1,'Accounting Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-05 09:00:00','2026-07-20 14:59:08'),
(1332,'COA-2016-125','Paper Shredder (Heavy Duty)',4,1,'2016-12-07',31687.38,4,'Manuel Bautista',NULL,'Human Resource Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-10 09:00:00','2026-07-17 18:12:48'),
(1333,'COA-2017-141','Electric Fan (Stand Type)',1,1,'2017-11-19',23821.45,6,'Gloria Flores',1,'Accounting Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2017-11-19 09:00:00','2026-07-20 14:59:08'),
(1334,'COA-2020-094','Bookshelf (Wooden, 5-Tier)',3,5,'2020-11-27',10776.83,6,NULL,5,'Accounting Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-30 09:00:00','2026-07-20 14:59:08'),
(1335,'COA-2026-064','Laminating Machine',4,1,'2026-03-02',62929.97,6,'Imelda Navarro',1,'Accounting Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-04 09:00:00','2026-07-20 14:59:08'),
(1336,'COA-2023-162','All-in-One Inkjet Printer',2,1,'2023-11-24',72872.94,15,'Cecilia Reyes',1,'General Services Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-25 09:00:00','2026-07-17 18:12:48'),
(1337,'COA-2020-095','Microwave Oven',1,1,'2020-05-27',52763.11,1,'Luz Ocampo',1,'Office of the Mayor - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2020-05-29 09:00:00','2026-07-20 14:59:08'),
(1338,'COA-2021-124','CCTV Camera (Outdoor)',7,1,'2021-09-05',32196.01,2,'Jose Santos',1,'Office of the Vice Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-07 09:00:00','2026-07-20 14:59:08'),
(1339,'COA-2022-126','Life Vest',10,1,'2022-02-12',34188.06,6,'Gloria Aquino',NULL,'Accounting Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-14 09:00:00','2026-07-17 18:12:48'),
(1340,'COA-2023-163','Fire Extinguisher (10lbs)',10,1,'2023-03-23',38993.86,1,'Gloria Gonzales',1,'Office of the Mayor - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-03-24 09:00:00','2026-07-17 18:12:48'),
(1341,'COA-2021-125','Binding Machine',4,1,'2021-08-13',46052.07,16,'Romeo Torres',1,'Information and Communications Technology Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-15 09:00:00','2026-07-17 18:12:48'),
(1342,'COA-2021-126','Water Cooler/Dispenser',1,1,'2021-07-03',22291.29,13,'Rosa Castillo',1,'Municipal Social Welfare and Development Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-07-05 09:00:00','2026-07-17 18:12:48'),
(1343,'COA-2020-096','Nebulizer Machine',8,1,'2020-04-03',31729.81,7,NULL,1,'Treasury Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-03 09:00:00','2026-07-17 18:12:48'),
(1344,'COA-2018-132','Emergency Light Tower',10,1,'2018-06-15',22582.98,5,'Ana Santos',1,'Budget Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-18 09:00:00','2026-07-20 14:59:08'),
(1345,'COA-2016-126','Generator Set (25 kVA)',6,1,'2016-01-24',2528270.47,8,'Gloria Aguilar',1,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-26 09:00:00','2026-07-20 14:59:08'),
(1346,'COA-2022-127','Photocopier Machine (Multi-function)',4,1,'2022-11-29',20458.57,5,'Gloria Pascual',1,'Budget Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-30 09:00:00','2026-07-20 14:59:08'),
(1347,'COA-2017-142','Steel Locker Cabinet',3,1,'2017-12-01',5688.65,3,'Alfredo Flores',1,'Sangguniang Bayan Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-03 09:00:00','2026-07-20 14:59:08'),
(1348,'COA-2016-127','Water Pump (Irrigation)',9,2,'2016-11-14',177053.04,6,NULL,NULL,'Accounting Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-17 09:00:00','2026-07-20 14:59:08'),
(1349,'COA-2018-133','Rice Thresher',9,2,'2018-01-11',127124.84,1,'Rodrigo Cruz',2,'Office of the Mayor - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-01-12 09:00:00','2026-07-20 14:59:08'),
(1350,'COA-2024-124','Fire Extinguisher (10lbs)',10,1,'2024-02-08',65834.78,16,'Teresa Bautista',1,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-08 09:00:00','2026-07-17 18:12:48'),
(1351,'COA-2023-164','Water Tanker Truck',6,1,'2023-09-28',827316.27,15,'Manuel Gonzales',1,'General Services Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-10-01 09:00:00','2026-07-17 18:12:48'),
(1352,'COA-2021-127','Calculator (Desktop Printing)',4,1,'2021-12-31',7164.46,16,NULL,NULL,'Information and Communications Technology Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-01 09:00:00','2026-07-17 18:12:48'),
(1353,'COA-2023-165','Service Vehicle (Sedan)',5,1,'2023-05-16',2192000.63,2,'Norma Salazar',1,'Office of the Vice Mayor - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-05-18 09:00:00','2026-07-17 18:12:48'),
(1354,'COA-2017-143','Swivel Office Chair',3,1,'2017-07-08',7952.58,8,'Josefa Ramos',1,'Assessor\'s Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-10 09:00:00','2026-07-20 14:59:08'),
(1355,'COA-2023-166','Backhoe Loader',6,1,'2023-11-11',2268409.84,7,'Norma Dela Cruz',NULL,'Treasury Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-11-13 09:00:00','2026-07-17 18:12:48'),
(1356,'COA-2025-116','Swivel Office Chair',3,1,'2025-07-23',20413.98,8,'Leonora Garcia',1,'Assessor\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2025-07-23 09:00:00','2026-07-20 14:59:08'),
(1357,'COA-2018-134','Vacuum Cleaner',1,1,'2018-11-04',12844.68,14,'Alfredo Reyes',1,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-07 09:00:00','2026-07-20 14:59:08'),
(1358,'COA-2022-128','Chainsaw (Rescue Type)',10,1,'2022-11-08',22854.78,4,'Imelda Dela Cruz',NULL,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2022-11-09 09:00:00','2026-07-17 18:12:48'),
(1359,'COA-2025-117','Base Radio Station',7,1,'2025-08-26',27236.71,2,NULL,NULL,'Office of the Vice Mayor - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-28 09:00:00','2026-07-17 18:12:48'),
(1360,'COA-2022-129','Ambulance Unit',5,1,'2022-12-14',1135793.60,3,'Jose Torres',NULL,'Sangguniang Bayan Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-15 09:00:00','2026-07-20 14:59:08'),
(1361,'COA-2021-128','Megaphone (Bullhorn)',7,1,'2021-03-01',39773.05,13,'Elena Marquez',1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-01 09:00:00','2026-07-17 18:12:48'),
(1362,'COA-2019-126','Dump Truck',5,1,'2019-05-15',513311.05,9,NULL,1,'Civil Registrar\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-17 09:00:00','2026-07-17 18:12:48'),
(1363,'COA-2023-167','Vacuum Cleaner',1,1,'2023-04-05',11281.93,10,'Leonora Mendoza',1,'Municipal Engineering Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-05 09:00:00','2026-07-20 14:59:08'),
(1364,'COA-2026-065','Megaphone (Bullhorn)',7,1,'2026-04-24',33900.87,5,NULL,NULL,'Budget Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-26 09:00:00','2026-07-20 12:47:01'),
(1365,'COA-2022-130','Refrigerator (2-Door)',1,1,'2022-08-30',41345.03,16,NULL,1,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-31 09:00:00','2026-07-20 14:59:08'),
(1366,'COA-2018-135','Base Radio Station',7,1,'2018-06-22',26287.49,9,'Romeo Garcia',1,'Civil Registrar\'s Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-22 09:00:00','2026-07-20 14:59:08'),
(1367,'COA-2018-136','Calculator (Desktop Printing)',4,1,'2018-12-03',61860.56,8,'Danilo Flores',1,'Assessor\'s Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-12-05 09:00:00','2026-07-20 14:59:08'),
(1368,'COA-2020-097','CCTV DVR/NVR Unit',7,1,'2020-03-11',13850.74,1,NULL,1,'Office of the Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-13 09:00:00','2026-07-17 18:12:48'),
(1369,'COA-2018-137','Multi-Purpose Van',5,1,'2018-03-27',2142345.09,11,'Eduardo Salazar',NULL,'Municipal Planning and Development Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-03-29 09:00:00','2026-07-20 14:59:08'),
(1370,'COA-2016-128','Service Pick-up Truck',5,1,'2016-11-19',1050700.71,5,'Cecilia Marquez',1,'Budget Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2016-11-19 09:00:00','2026-07-20 12:47:01'),
(1371,'COA-2022-131','Swivel Office Chair',3,1,'2022-09-06',22278.93,13,'Manuel Domingo',1,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-09 09:00:00','2026-07-20 14:59:08'),
(1372,'COA-2018-138','Multi-Purpose Van',5,1,'2018-09-08',1809609.37,5,'Ana Ramos',NULL,'Budget Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-11 09:00:00','2026-07-20 14:59:08'),
(1373,'COA-2018-139','Emergency Light Tower',10,1,'2018-10-12',85445.24,7,NULL,1,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-15 09:00:00','2026-07-17 18:12:48'),
(1374,'COA-2018-140','Paper Shredder (Heavy Duty)',4,1,'2018-07-14',62585.13,15,'Juan Dela Cruz',1,'General Services Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-15 09:00:00','2026-07-17 18:12:48'),
(1375,'COA-2020-098','UPS (Uninterruptible Power Supply)',2,1,'2020-02-17',41837.46,3,NULL,1,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-19 09:00:00','2026-07-17 18:12:48'),
(1376,'COA-2024-125','PABX Telephone System',7,1,'2024-12-10',13539.87,17,'Rodrigo Del Rosario',1,'Disaster Risk Reduction and Management Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-12-11 09:00:00','2026-07-17 18:12:48'),
(1377,'COA-2020-099','Electric Kettle',1,1,'2020-08-10',48453.88,17,'Elena Pascual',1,'Disaster Risk Reduction and Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-12 09:00:00','2026-07-17 18:12:48'),
(1378,'COA-2026-066','Desktop Computer Set (Core i5)',2,1,'2026-03-20',57365.03,9,'Ernesto Fernandez',1,'Civil Registrar\'s Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-23 09:00:00','2026-07-17 18:12:48'),
(1379,'COA-2016-129','Water Dispenser (Hot & Cold)',1,1,'2016-04-13',27901.86,2,'Norma Garcia',1,'Office of the Vice Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2016-04-15 09:00:00','2026-07-17 18:12:48'),
(1380,'COA-2024-126','Calculator (Desktop Printing)',4,1,'2024-08-16',50309.96,4,'Rodrigo Marquez',1,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-16 09:00:00','2026-07-20 14:59:08'),
(1381,'COA-2024-127','Steel Locker Cabinet',3,1,'2024-09-11',25493.78,17,'Rodrigo Mendoza',NULL,'Disaster Risk Reduction and Management Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-13 09:00:00','2026-07-20 14:59:08'),
(1382,'COA-2026-067','Road Roller',6,1,'2026-03-14',772822.01,7,'Danilo Pascual',1,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-14 09:00:00','2026-07-17 18:12:48'),
(1383,'COA-2024-128','Nebulizer Machine',8,1,'2024-10-07',28221.97,8,'Teresa Santos',1,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-09 09:00:00','2026-07-17 18:12:48'),
(1384,'COA-2020-100','Seedling Tray Set',9,2,'2020-05-12',142566.50,6,'Ricardo Mendoza',2,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-13 09:00:00','2026-07-17 18:12:48'),
(1385,'COA-2026-068','Seedling Tray Set',9,5,'2026-01-05',115069.18,8,'Jose Salazar',5,'Assessor\'s Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-08 09:00:00','2026-07-20 14:59:08'),
(1386,'COA-2017-144','Oxygen Tank with Regulator',8,1,'2017-06-20',26363.69,9,NULL,NULL,'Civil Registrar\'s Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2017-06-23 09:00:00','2026-07-20 14:59:08'),
(1387,'COA-2018-141','Rescue Rope Kit',10,1,'2018-11-05',34187.87,10,NULL,1,'Municipal Engineering Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-05 09:00:00','2026-07-17 18:12:48'),
(1388,'COA-2016-130','Water Tanker Truck',6,1,'2016-08-22',871665.36,13,NULL,NULL,'Municipal Social Welfare and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-23 09:00:00','2026-07-20 14:59:08'),
(1389,'COA-2016-131','Weighing Scale (Digital)',8,1,'2016-09-30',64491.36,8,'Imelda Salazar',1,'Assessor\'s Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-02 09:00:00','2026-07-20 14:59:08'),
(1390,'COA-2023-168','Motorcycle (Service Unit)',5,1,'2023-04-29',1016928.02,4,'Imelda Santos',1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-01 09:00:00','2026-07-17 18:12:48'),
(1391,'COA-2023-169','Life Vest',10,1,'2023-05-14',37908.82,16,'Ramon Salazar',1,'Information and Communications Technology Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2023-05-17 09:00:00','2026-07-20 14:59:08'),
(1392,'COA-2016-132','Handheld Two-Way Radio',7,1,'2016-10-21',26564.62,9,NULL,1,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-24 09:00:00','2026-07-17 18:12:48'),
(1393,'COA-2021-129','Bulletin Board (Cork, Framed)',4,1,'2021-01-20',25180.67,11,'Josefa Dela Cruz',1,'Municipal Planning and Development Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-01-23 09:00:00','2026-07-17 18:12:48'),
(1394,'COA-2017-145','Laser Printer (Monochrome)',2,1,'2017-01-28',63859.20,16,'Luz Santos',1,'Information and Communications Technology Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-29 09:00:00','2026-07-20 14:59:08'),
(1395,'COA-2016-133','Thermal Scanner',8,1,'2016-05-28',27050.90,13,'Josefa Salazar',1,'Municipal Social Welfare and Development Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-05-28 09:00:00','2026-07-17 18:12:48'),
(1396,'COA-2021-130','IP Desk Phone',7,1,'2021-02-28',32056.75,1,NULL,1,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-03 09:00:00','2026-07-17 18:12:48'),
(1397,'COA-2018-142','Fire Extinguisher (10lbs)',10,1,'2018-04-11',58043.47,10,'Manuel Castillo',1,'Municipal Engineering Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-14 09:00:00','2026-07-20 14:59:08'),
(1398,'COA-2016-134','Laser Printer (Monochrome)',2,1,'2016-07-06',16442.01,5,'Alfredo Dela Cruz',1,'Budget Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-09 09:00:00','2026-07-20 14:59:08'),
(1399,'COA-2023-170','Digital Blood Pressure Monitor',8,1,'2023-12-22',1641.09,1,'Cecilia Pascual',1,'Office of the Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-24 09:00:00','2026-07-17 18:12:48'),
(1400,'COA-2025-118','Weighing Scale (Digital)',8,1,'2025-12-03',51245.07,10,'Romeo Aquino',1,'Municipal Engineering Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-03 09:00:00','2026-07-20 14:59:08'),
(1401,'COA-2021-131','Road Roller',6,1,'2021-04-10',457259.91,8,'Ramon Navarro',1,'Assessor\'s Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-10 09:00:00','2026-07-20 14:59:08'),
(1402,'COA-2018-143','Bookshelf (Wooden, 5-Tier)',3,1,'2018-07-01',2527.82,13,'Francisco Ocampo',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-01 09:00:00','2026-07-17 18:12:48'),
(1403,'COA-2016-135','Patrol Motorcycle',5,1,'2016-11-16',999523.74,8,'Ricardo Cruz',1,'Assessor\'s Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-19 09:00:00','2026-07-20 14:59:08'),
(1404,'COA-2019-127','Binding Machine',4,1,'2019-09-15',57228.86,10,NULL,1,'Municipal Engineering Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-17 09:00:00','2026-07-17 18:12:48'),
(1405,'COA-2024-129','Chainsaw (Rescue Type)',10,1,'2024-06-11',24548.60,8,'Leonora Ramos',1,'Assessor\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2024-06-11 09:00:00','2026-07-17 18:12:48'),
(1406,'COA-2016-136','Bookshelf (Wooden, 5-Tier)',3,5,'2016-07-14',12459.44,8,'Josefa Ocampo',5,'Assessor\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-16 09:00:00','2026-07-17 18:12:48'),
(1407,'COA-2018-144','Service Pick-up Truck',5,1,'2018-10-17',631319.85,4,'Romeo Navarro',1,'Human Resource Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-17 09:00:00','2026-07-20 14:59:08'),
(1408,'COA-2018-145','Water Pump (Irrigation)',9,2,'2018-02-28',68901.02,12,'Eduardo Garcia',2,'Municipal Health Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-03-03 09:00:00','2026-07-17 18:12:48'),
(1409,'COA-2016-137','Service Pick-up Truck',5,1,'2016-09-19',1716185.37,13,'Maria Dela Cruz',1,'Municipal Social Welfare and Development Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-20 09:00:00','2026-07-20 14:59:08'),
(1410,'COA-2025-119','Bulldozer',6,1,'2025-09-10',1856980.29,13,'Carlos Castillo',NULL,'Municipal Social Welfare and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2025-09-11 09:00:00','2026-07-17 18:12:48'),
(1411,'COA-2023-171','24-Port Network Switch',2,1,'2023-12-01',50098.94,9,'Danilo Castillo',1,'Civil Registrar\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-12-03 09:00:00','2026-07-17 18:12:48'),
(1412,'COA-2018-146','Patrol Motorcycle',5,1,'2018-02-19',1162942.45,6,NULL,1,'Accounting Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-02-22 09:00:00','2026-07-17 18:12:48'),
(1413,'COA-2018-147','Dump Truck',5,1,'2018-05-01',638617.51,14,'Imelda Pascual',NULL,'Municipal Agriculture Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-01 09:00:00','2026-07-20 14:59:08'),
(1414,'COA-2022-132','Electric Kettle',1,1,'2022-03-11',39814.67,2,NULL,1,'Office of the Vice Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-13 09:00:00','2026-07-17 18:12:48'),
(1415,'COA-2016-138','Thermal Scanner',8,1,'2016-09-20',32724.27,10,NULL,NULL,'Municipal Engineering Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-20 09:00:00','2026-07-17 18:12:48'),
(1416,'COA-2017-146','Microwave Oven',1,1,'2017-10-25',24661.53,6,'Francisco Castillo',1,'Accounting Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-27 09:00:00','2026-07-20 14:59:08'),
(1417,'COA-2020-101','Steel Filing Cabinet (4-Drawer)',3,1,'2020-07-01',6678.22,11,'Juan Flores',1,'Municipal Planning and Development Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-01 09:00:00','2026-07-20 14:59:08'),
(1418,'COA-2025-120','Digital Blood Pressure Monitor',8,1,'2025-02-23',53348.44,12,'Ernesto Salazar',1,'Municipal Health Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-02-23 09:00:00','2026-07-20 14:59:08'),
(1419,'COA-2016-139','Backhoe Loader',6,1,'2016-08-17',3033452.07,7,'Elena Ocampo',1,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-20 09:00:00','2026-07-17 18:12:48'),
(1420,'COA-2017-147','Conference Table (8-Seater)',3,2,'2017-06-04',3025.12,2,NULL,2,'Office of the Vice Mayor - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-04 09:00:00','2026-07-20 14:59:08'),
(1421,'COA-2019-128','Executive Office Desk',3,1,'2019-04-13',2767.52,5,'Norma Aguilar',NULL,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-14 09:00:00','2026-07-20 12:47:01'),
(1422,'COA-2025-121','Wheelchair',8,1,'2025-04-01',50549.52,11,'Alfredo Cruz',1,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-02 09:00:00','2026-07-17 18:12:48'),
(1423,'COA-2023-172','Swivel Office Chair',3,1,'2023-01-20',14755.15,16,NULL,1,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-21 09:00:00','2026-07-20 14:59:08'),
(1424,'COA-2026-069','Motorcycle (Service Unit)',5,1,'2026-04-05',1718237.42,9,'Elena Salazar',1,'Civil Registrar\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2026-04-05 09:00:00','2026-07-17 18:12:48'),
(1425,'COA-2021-132','UPS (Uninterruptible Power Supply)',2,1,'2021-02-18',10273.16,17,'Danilo Gonzales',NULL,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2021-02-19 09:00:00','2026-07-20 14:59:08'),
(1426,'COA-2023-173','Digital Blood Pressure Monitor',8,1,'2023-10-11',96055.62,10,NULL,1,'Municipal Engineering Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-13 09:00:00','2026-07-20 14:59:08'),
(1427,'COA-2021-133','Backhoe Loader',6,1,'2021-07-16',842090.94,4,'Josefa Domingo',1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-16 09:00:00','2026-07-17 18:12:48'),
(1428,'COA-2023-174','Bookshelf (Wooden, 5-Tier)',3,1,'2023-08-13',17041.55,13,'Leonora Torres',NULL,'Municipal Social Welfare and Development Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-14 09:00:00','2026-07-17 18:12:48'),
(1429,'COA-2019-129','Thermal Scanner',8,1,'2019-06-02',61766.09,1,'Antonio Dela Cruz',1,'Office of the Mayor - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-02 09:00:00','2026-07-20 14:59:08'),
(1430,'COA-2022-133','Concrete Mixer',6,1,'2022-11-12',2843624.51,3,'Imelda Pascual',1,'Sangguniang Bayan Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-12 09:00:00','2026-07-17 18:12:48'),
(1431,'COA-2020-102','Rescue Rope Kit',10,1,'2020-08-23',26924.69,11,'Josefa Salazar',1,'Municipal Planning and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-24 09:00:00','2026-07-17 18:12:48'),
(1432,'COA-2017-148','Concrete Mixer',6,1,'2017-08-03',2073071.50,3,'Carmen Navarro',NULL,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-05 09:00:00','2026-07-20 14:59:08'),
(1433,'COA-2017-149','Laminating Machine',4,1,'2017-09-13',22579.89,2,'Eduardo Domingo',1,'Office of the Vice Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-13 09:00:00','2026-07-17 18:12:48'),
(1434,'COA-2016-140','Ambulance Unit',5,1,'2016-06-24',1109720.62,6,'Ramon Cruz',1,'Accounting Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-06-24 09:00:00','2026-07-17 18:12:48'),
(1435,'COA-2023-175','UPS (Uninterruptible Power Supply)',2,1,'2023-05-05',66302.08,8,'Ramon Navarro',NULL,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2023-05-05 09:00:00','2026-07-20 14:59:08'),
(1436,'COA-2024-130','Laptop Computer (Business Series)',2,1,'2024-10-08',36024.83,6,'Imelda Bautista',NULL,'Accounting Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-10-10 09:00:00','2026-07-20 14:59:08'),
(1437,'COA-2024-131','Refrigerator (2-Door)',1,1,'2024-07-24',30369.01,4,'Cecilia Reyes',1,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-27 09:00:00','2026-07-20 14:59:08'),
(1438,'COA-2026-070','Partition Divider Panel',3,2,'2026-04-08',18305.93,17,'Alfredo Castillo',NULL,'Disaster Risk Reduction and Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-10 09:00:00','2026-07-17 18:12:48'),
(1439,'COA-2022-134','Ambulance Unit',5,1,'2022-09-06',1717385.82,4,'Imelda Mendoza',1,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-09 09:00:00','2026-07-17 18:12:48'),
(1440,'COA-2016-141','Multi-Purpose Van',5,1,'2016-07-05',735416.51,3,'Carlos Bautista',1,'Sangguniang Bayan Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-06 09:00:00','2026-07-20 14:59:08'),
(1441,'COA-2025-122','Autoclave Sterilizer',8,1,'2025-04-03',71193.11,5,'Corazon Ramos',1,'Budget Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-03 09:00:00','2026-07-20 12:47:01'),
(1442,'COA-2025-123','Vacuum Cleaner',1,1,'2025-10-24',24668.04,8,'Danilo Ocampo',1,'Assessor\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-26 09:00:00','2026-07-17 18:12:48'),
(1443,'COA-2018-148','Hand Tractor',9,1,'2018-02-11',60291.61,13,'Divina Mendoza',NULL,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-13 09:00:00','2026-07-17 18:12:48'),
(1444,'COA-2025-124','Swivel Office Chair',3,5,'2025-06-12',21763.81,14,'Francisco Domingo',5,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-06-14 09:00:00','2026-07-17 18:12:48'),
(1445,'COA-2025-125','Seedling Tray Set',9,5,'2025-11-21',161106.88,7,'Romeo Torres',5,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-22 09:00:00','2026-07-17 18:12:48'),
(1446,'COA-2017-150','Sprayer (Backpack, Motorized)',9,2,'2017-12-26',21989.23,13,'Luz Bautista',2,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-27 09:00:00','2026-07-17 18:12:48'),
(1447,'COA-2017-151','Metal Detector (Handheld)',10,1,'2017-02-10',52272.48,5,'Elena Aquino',1,'Budget Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-13 09:00:00','2026-07-20 14:59:08'),
(1448,'COA-2026-071','Water Cooler/Dispenser',1,1,'2026-01-16',28382.94,13,'Maria Aguilar',1,'Municipal Social Welfare and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-17 09:00:00','2026-07-17 18:12:48'),
(1449,'COA-2024-132','Service Vehicle (Sedan)',5,1,'2024-08-21',1537047.34,8,'Francisco Aguilar',1,'Assessor\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-21 09:00:00','2026-07-20 14:59:08'),
(1450,'COA-2019-130','Bulletin Board (Cork, Framed)',4,1,'2019-12-04',14048.09,10,'Danilo Ocampo',1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-06 09:00:00','2026-07-17 18:12:48'),
(1451,'COA-2022-135','Emergency Light Tower',10,1,'2022-06-12',10760.67,12,'Carlos Villanueva',1,'Municipal Health Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-15 09:00:00','2026-07-20 14:59:08'),
(1452,'COA-2024-133','PABX Telephone System',7,1,'2024-07-26',33872.40,1,NULL,NULL,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-28 09:00:00','2026-07-17 18:12:48'),
(1453,'COA-2016-142','Emergency Light Tower',10,1,'2016-09-14',42722.17,10,'Josefa Dela Cruz',1,'Municipal Engineering Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2016-09-17 09:00:00','2026-07-17 18:12:48'),
(1454,'COA-2022-136','Nebulizer Machine',8,1,'2022-04-09',82741.70,9,NULL,NULL,'Civil Registrar\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-04-11 09:00:00','2026-07-17 18:12:48'),
(1455,'COA-2021-134','All-in-One Inkjet Printer',2,1,'2021-03-07',29540.07,14,'Rodrigo Castillo',NULL,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-09 09:00:00','2026-07-20 14:59:08'),
(1456,'COA-2018-149','Life Vest',10,1,'2018-12-22',31391.45,1,'Rosa Del Rosario',NULL,'Office of the Mayor - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-25 09:00:00','2026-07-20 14:59:08'),
(1457,'COA-2017-152','Partition Divider Panel',3,1,'2017-07-25',11831.76,13,'Corazon Reyes',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-27 09:00:00','2026-07-17 18:12:48'),
(1458,'COA-2025-126','Electric Fan (Stand Type)',1,1,'2025-10-23',19818.70,7,'Alfredo Gonzales',NULL,'Treasury Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-25 09:00:00','2026-07-17 18:12:48'),
(1459,'COA-2025-127','Road Roller',6,1,'2025-09-15',391521.33,14,NULL,1,'Municipal Agriculture Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-16 09:00:00','2026-07-20 14:59:08'),
(1460,'COA-2022-137','Megaphone (Bullhorn)',7,1,'2022-08-22',35588.56,4,'Carlos Dela Cruz',NULL,'Human Resource Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-25 09:00:00','2026-07-17 18:12:48'),
(1461,'COA-2021-135','Motorcycle (Service Unit)',5,1,'2021-01-12',540626.05,14,'Gloria Ocampo',NULL,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2021-01-13 09:00:00','2026-07-17 18:12:48'),
(1462,'COA-2025-128','CCTV DVR/NVR Unit',7,1,'2025-12-18',7722.20,12,'Gloria Villanueva',1,'Municipal Health Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-19 09:00:00','2026-07-17 18:12:48'),
(1463,'COA-2022-138','Water Tanker Truck',6,1,'2022-04-07',2682725.58,14,'Luz Reyes',1,'Municipal Agriculture Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-04-08 09:00:00','2026-07-20 14:59:08'),
(1464,'COA-2019-131','Autoclave Sterilizer',8,1,'2019-07-15',92522.03,5,'Leonora Mendoza',1,'Budget Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-07-16 09:00:00','2026-07-20 12:47:01'),
(1465,'COA-2021-136','Microwave Oven',1,1,'2021-08-05',27721.02,9,'Cecilia Villanueva',NULL,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-07 09:00:00','2026-07-17 18:12:48'),
(1466,'COA-2019-132','Hand Tractor',9,2,'2019-07-04',150072.08,8,NULL,NULL,'Assessor\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-07-07 09:00:00','2026-07-20 14:59:08'),
(1467,'COA-2020-103','Water Dispenser (Hot & Cold)',1,1,'2020-06-03',37066.63,8,NULL,1,'Assessor\'s Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-06-05 09:00:00','2026-07-20 14:59:08'),
(1468,'COA-2020-104','Wheelchair',8,1,'2020-10-09',65024.50,6,'Elena Cruz',1,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-09 09:00:00','2026-07-17 18:12:48'),
(1469,'COA-2017-153','Bookshelf (Wooden, 5-Tier)',3,1,'2017-07-27',12082.95,12,NULL,1,'Municipal Health Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-27 09:00:00','2026-07-17 18:12:48'),
(1470,'COA-2022-139','Backhoe Loader',6,1,'2022-09-20',1086230.11,10,'Ramon Salazar',1,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-21 09:00:00','2026-07-17 18:12:48'),
(1471,'COA-2025-129','Patrol Motorcycle',5,1,'2025-05-06',1927182.80,4,'Eduardo Villanueva',1,'Human Resource Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-08 09:00:00','2026-07-20 14:59:08'),
(1472,'COA-2018-150','Rice Thresher',9,1,'2018-06-29',97018.73,1,'Leonora Santos',1,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2018-06-30 09:00:00','2026-07-20 14:59:08'),
(1473,'COA-2025-130','Seedling Tray Set',9,1,'2025-02-08',65738.56,6,'Cecilia Salazar',1,'Accounting Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-02-08 09:00:00','2026-07-20 14:59:08'),
(1474,'COA-2018-151','Laptop Computer (Business Series)',2,1,'2018-01-13',41723.29,11,'Antonio Del Rosario',1,'Municipal Planning and Development Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-14 09:00:00','2026-07-17 18:12:48'),
(1475,'COA-2019-133','Inflatable Rescue Boat',10,1,'2019-12-30',65756.99,4,'Ramon Domingo',NULL,'Human Resource Management Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-01-01 09:00:00','2026-07-17 18:12:48'),
(1476,'COA-2022-140','Fire Extinguisher (10lbs)',10,1,'2022-08-08',93785.13,13,'Alfredo Domingo',1,'Municipal Social Welfare and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-08 09:00:00','2026-07-20 14:59:08'),
(1477,'COA-2023-176','Electric Fan (Stand Type)',1,1,'2023-09-25',8388.69,1,'Cecilia Castillo',1,'Office of the Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-26 09:00:00','2026-07-20 14:59:08'),
(1478,'COA-2023-177','Seedling Tray Set',9,1,'2023-06-10',163162.27,14,'Luz Domingo',NULL,'Municipal Agriculture Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-10 09:00:00','2026-07-17 18:12:48'),
(1479,'COA-2022-141','Life Vest',10,1,'2022-07-15',42737.76,15,'Romeo Aquino',NULL,'General Services Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-15 09:00:00','2026-07-17 18:12:48'),
(1480,'COA-2018-152','Rescue Rope Kit',10,1,'2018-01-03',8645.51,2,'Francisco Ocampo',NULL,'Office of the Vice Mayor - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-06 09:00:00','2026-07-20 14:59:08'),
(1481,'COA-2023-178','Seedling Tray Set',9,2,'2023-03-03',162122.97,7,'Gloria Castillo',2,'Treasury Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-03 09:00:00','2026-07-20 14:59:08'),
(1482,'COA-2021-137','Typewriter (Manual)',4,1,'2021-07-26',35430.48,14,'Ricardo Bautista',1,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-29 09:00:00','2026-07-20 14:59:08'),
(1483,'COA-2024-134','Hand Tractor',9,5,'2024-09-10',46876.94,4,NULL,5,'Human Resource Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-12 09:00:00','2026-07-20 14:59:08'),
(1484,'COA-2025-131','Fire Extinguisher (10lbs)',10,1,'2025-05-06',43412.42,6,'Carmen Castillo',NULL,'Accounting Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-08 09:00:00','2026-07-17 18:12:48'),
(1485,'COA-2022-142','Concrete Mixer',6,1,'2022-01-14',408902.46,17,'Norma Dela Cruz',1,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-14 09:00:00','2026-07-20 14:59:08'),
(1486,'COA-2016-143','Rescue Rope Kit',10,1,'2016-02-12',91142.91,3,'Leonora Navarro',NULL,'Sangguniang Bayan Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2016-02-13 09:00:00','2026-07-17 18:12:48'),
(1487,'COA-2025-132','Seedling Tray Set',9,1,'2025-04-07',154510.80,11,'Maria Villanueva',1,'Municipal Planning and Development Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-04-09 09:00:00','2026-07-17 18:12:48'),
(1488,'COA-2026-072','IP Desk Phone',7,1,'2026-02-27',42138.31,3,'Ricardo Salazar',1,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-28 09:00:00','2026-07-20 14:59:08'),
(1489,'COA-2022-143','Rescue Rope Kit',10,1,'2022-05-16',21435.68,13,'Corazon Reyes',NULL,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-18 09:00:00','2026-07-20 14:59:08'),
(1490,'COA-2021-138','Generator Set (25 kVA)',6,1,'2021-01-18',1051984.23,10,'Leonora Domingo',NULL,'Municipal Engineering Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-18 09:00:00','2026-07-17 18:12:48'),
(1491,'COA-2020-105','Dump Truck',5,1,'2020-05-28',1523527.56,8,'Alfredo Rivera',1,'Assessor\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-31 09:00:00','2026-07-20 14:59:08'),
(1492,'COA-2016-144','IP Desk Phone',7,1,'2016-01-20',41349.79,14,'Ricardo Santos',1,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-01-23 09:00:00','2026-07-20 14:59:08'),
(1493,'COA-2019-134','Metal Detector (Handheld)',10,1,'2019-08-17',84922.86,15,'Leonora Fernandez',1,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-18 09:00:00','2026-07-20 14:59:08'),
(1494,'COA-2017-154','Sprayer (Backpack, Motorized)',9,1,'2017-07-08',4960.11,1,'Teresa Torres',1,'Office of the Mayor - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-09 09:00:00','2026-07-20 14:59:08'),
(1495,'COA-2021-139','Stretcher (Foldable)',8,1,'2021-12-06',71649.35,4,'Gloria Dela Cruz',1,'Human Resource Management Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-08 09:00:00','2026-07-20 14:59:08'),
(1496,'COA-2022-144','Rescue Rope Kit',10,1,'2022-05-22',18101.39,1,'Leonora Ramos',1,'Office of the Mayor - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-23 09:00:00','2026-07-20 14:59:08'),
(1497,'COA-2017-155','Concrete Mixer',6,1,'2017-07-10',1749235.94,15,'Romeo Torres',1,'General Services Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-10 09:00:00','2026-07-17 18:12:48'),
(1498,'COA-2024-135','CCTV DVR/NVR Unit',7,1,'2024-09-12',35040.83,9,'Luz Torres',1,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-15 09:00:00','2026-07-20 14:59:08'),
(1499,'COA-2018-153','Generator Set (25 kVA)',6,1,'2018-06-30',1017003.81,17,'Ernesto Salazar',1,'Disaster Risk Reduction and Management Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-06-30 09:00:00','2026-07-17 18:12:48'),
(1500,'COA-2019-135','Air Conditioning Unit (1.5HP Split Type)',1,1,'2019-11-30',29414.18,4,'Teresa Dela Cruz',NULL,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-01 09:00:00','2026-07-17 18:12:48'),
(1501,'COA-2025-133','All-in-One Inkjet Printer',2,1,'2025-09-02',76766.22,6,'Norma Fernandez',1,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-02 09:00:00','2026-07-17 18:12:48'),
(1502,'COA-2017-156','Stretcher (Foldable)',8,1,'2017-02-12',20407.98,9,'Ernesto Flores',1,'Civil Registrar\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-13 09:00:00','2026-07-17 18:12:48'),
(1503,'COA-2024-136','Conference Table (8-Seater)',3,5,'2024-06-01',26716.76,5,'Norma Ocampo',5,'Budget Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-01 09:00:00','2026-07-20 12:47:01'),
(1504,'COA-2016-145','Partition Divider Panel',3,1,'2016-11-16',22464.48,12,'Juan Ramos',1,'Municipal Health Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-19 09:00:00','2026-07-17 18:12:48'),
(1505,'COA-2017-157','Farm Tool Kit',9,2,'2017-02-10',41467.31,14,'Pedro Gonzales',NULL,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2017-02-10 09:00:00','2026-07-20 14:59:08'),
(1506,'COA-2026-073','Fax Machine',4,1,'2026-01-06',47729.39,13,'Carmen Torres',1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2026-01-09 09:00:00','2026-07-20 14:59:08'),
(1507,'COA-2017-158','Nebulizer Machine',8,1,'2017-07-13',114704.82,8,'Juan Dela Cruz',1,'Assessor\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-14 09:00:00','2026-07-17 18:12:48'),
(1508,'COA-2018-154','UPS (Uninterruptible Power Supply)',2,1,'2018-04-16',70413.76,4,'Norma Rivera',1,'Human Resource Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-17 09:00:00','2026-07-17 18:12:48'),
(1509,'COA-2024-137','Water Tanker Truck',6,1,'2024-05-03',2608189.46,9,NULL,1,'Civil Registrar\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-04 09:00:00','2026-07-20 14:59:08'),
(1510,'COA-2017-159','Megaphone (Bullhorn)',7,1,'2017-08-15',12087.27,2,'Leonora Garcia',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-15 09:00:00','2026-07-17 18:12:48'),
(1511,'COA-2017-160','Dump Truck',5,1,'2017-08-04',2049259.19,3,'Juan Navarro',1,'Sangguniang Bayan Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-07 09:00:00','2026-07-20 14:59:08'),
(1512,'COA-2020-106','Laminating Machine',4,1,'2020-09-19',22579.99,6,'Pedro Salazar',NULL,'Accounting Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-09-22 09:00:00','2026-07-17 18:12:48'),
(1513,'COA-2019-136','Electric Kettle',1,1,'2019-01-12',45925.97,5,'Cecilia Aquino',1,'Budget Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-12 09:00:00','2026-07-20 14:59:08'),
(1514,'COA-2017-161','Emergency Light Tower',10,1,'2017-11-30',41977.64,3,NULL,1,'Sangguniang Bayan Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-30 09:00:00','2026-07-20 14:59:08'),
(1515,'COA-2017-162','Rice Thresher',9,2,'2017-06-03',70458.66,14,'Juan Rivera',2,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-03 09:00:00','2026-07-20 14:59:08'),
(1516,'COA-2022-145','Desktop Computer Set (Core i5)',2,1,'2022-05-31',45274.26,4,'Eduardo Garcia',NULL,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-31 09:00:00','2026-07-17 18:12:48'),
(1517,'COA-2022-146','Typewriter (Manual)',4,1,'2022-10-26',54683.55,13,'Elena Ramos',1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-27 09:00:00','2026-07-17 18:12:48'),
(1518,'COA-2020-107','Life Vest',10,1,'2020-08-07',27511.86,17,'Danilo Dela Cruz',1,'Disaster Risk Reduction and Management Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-08-08 09:00:00','2026-07-17 18:12:48'),
(1519,'COA-2020-108','Bookshelf (Wooden, 5-Tier)',3,1,'2020-01-11',24747.80,1,'Juan Reyes',1,'Office of the Mayor - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-01-12 09:00:00','2026-07-17 18:12:48'),
(1520,'COA-2018-155','CCTV Camera (Outdoor)',7,1,'2018-09-07',7227.27,15,'Ricardo Rivera',1,'General Services Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2018-09-10 09:00:00','2026-07-20 14:59:08'),
(1521,'COA-2025-134','Base Radio Station',7,1,'2025-03-14',8401.71,5,'Gloria Pascual',NULL,'Budget Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2025-03-17 09:00:00','2026-07-20 14:59:08'),
(1522,'COA-2019-137','Seedling Tray Set',9,1,'2019-05-14',169904.69,11,NULL,NULL,'Municipal Planning and Development Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-14 09:00:00','2026-07-20 14:59:08'),
(1523,'COA-2019-138','Metal Detector (Handheld)',10,1,'2019-02-09',22377.98,17,'Romeo Bautista',1,'Disaster Risk Reduction and Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-10 09:00:00','2026-07-20 14:59:08'),
(1524,'COA-2023-179','Water Pump (Irrigation)',9,1,'2023-10-14',91970.36,12,'Divina Villanueva',1,'Municipal Health Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-16 09:00:00','2026-07-17 18:12:48'),
(1525,'COA-2019-139','Water Tanker Truck',6,1,'2019-02-11',1521680.06,8,'Manuel Navarro',NULL,'Assessor\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-14 09:00:00','2026-07-20 14:59:08'),
(1526,'COA-2017-163','Executive Office Desk',3,5,'2017-01-26',4897.01,2,NULL,5,'Office of the Vice Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-28 09:00:00','2026-07-17 18:12:48'),
(1527,'COA-2021-140','Binding Machine',4,1,'2021-01-03',63025.05,17,'Romeo Domingo',1,'Disaster Risk Reduction and Management Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-01-04 09:00:00','2026-07-17 18:12:48'),
(1528,'COA-2021-141','Road Roller',6,1,'2021-03-30',2600555.59,5,'Carlos Aguilar',1,'Budget Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2021-04-01 09:00:00','2026-07-20 14:59:08'),
(1529,'COA-2022-147','Farm Tool Kit',9,1,'2022-03-09',22417.78,5,'Teresa Santos',1,'Budget Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2022-03-12 09:00:00','2026-07-20 14:59:08'),
(1530,'COA-2018-156','Fire Extinguisher (10lbs)',10,1,'2018-06-16',26598.70,6,'Maria Santos',1,'Accounting Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-18 09:00:00','2026-07-17 18:12:48'),
(1531,'COA-2016-146','Life Vest',10,1,'2016-10-08',10330.13,14,'Romeo Ramos',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-10 09:00:00','2026-07-17 18:12:48'),
(1532,'COA-2020-109','Dump Truck',5,1,'2020-04-12',530506.12,10,NULL,1,'Municipal Engineering Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-12 09:00:00','2026-07-20 14:59:08'),
(1533,'COA-2022-148','Refrigerator (2-Door)',1,1,'2022-12-22',19977.06,4,'Josefa Ocampo',1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-22 09:00:00','2026-07-20 14:59:08'),
(1534,'COA-2021-142','PABX Telephone System',7,1,'2021-07-04',25227.22,3,'Antonio Bautista',1,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-05 09:00:00','2026-07-17 18:12:48'),
(1535,'COA-2019-140','CCTV DVR/NVR Unit',7,1,'2019-12-09',35784.80,13,NULL,NULL,'Municipal Social Welfare and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-11 09:00:00','2026-07-20 14:59:08'),
(1536,'COA-2021-143','Water Pump (Irrigation)',9,5,'2021-09-22',55294.24,15,'Jose Del Rosario',NULL,'General Services Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-24 09:00:00','2026-07-17 18:12:48'),
(1537,'COA-2019-141','Rescue Rope Kit',10,1,'2019-05-19',13676.53,16,'Ramon Torres',NULL,'Information and Communications Technology Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-05-22 09:00:00','2026-07-17 18:12:48'),
(1538,'COA-2017-164','Rice Thresher',9,1,'2017-03-28',62853.14,5,'Alfredo Ramos',1,'Budget Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-29 09:00:00','2026-07-20 12:47:01'),
(1539,'COA-2023-180','Patrol Motorcycle',5,1,'2023-03-17',603897.47,10,'Imelda Marquez',1,'Municipal Engineering Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2023-03-20 09:00:00','2026-07-17 18:12:48'),
(1540,'COA-2018-157','Laminating Machine',4,1,'2018-07-12',44984.43,10,'Ricardo Rivera',1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-13 09:00:00','2026-07-17 18:12:48'),
(1541,'COA-2025-135','Megaphone (Bullhorn)',7,1,'2025-09-17',3277.18,9,'Alfredo Bautista',1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-20 09:00:00','2026-07-20 14:59:08'),
(1542,'COA-2018-158','Desktop Computer Set (Core i5)',2,1,'2018-10-09',16240.18,6,'Luz Cruz',NULL,'Accounting Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-10 09:00:00','2026-07-20 14:59:08'),
(1543,'COA-2016-147','Hand Tractor',9,1,'2016-08-04',32296.97,13,NULL,NULL,'Municipal Social Welfare and Development Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2016-08-06 09:00:00','2026-07-20 14:59:08'),
(1544,'COA-2026-074','Bulletin Board (Cork, Framed)',4,1,'2026-04-22',53424.07,10,'Ernesto Marquez',1,'Municipal Engineering Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-22 09:00:00','2026-07-17 18:12:48'),
(1545,'COA-2025-136','Laser Printer (Monochrome)',2,1,'2025-11-30',66323.65,13,NULL,1,'Municipal Social Welfare and Development Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-01 09:00:00','2026-07-20 14:59:08'),
(1546,'COA-2019-142','Nebulizer Machine',8,1,'2019-09-08',110669.84,17,'Jose Torres',1,'Disaster Risk Reduction and Management Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-09 09:00:00','2026-07-17 18:12:48'),
(1547,'COA-2021-144','Farm Tool Kit',9,1,'2021-11-10',86750.44,15,'Corazon Reyes',NULL,'General Services Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-11-12 09:00:00','2026-07-20 14:59:08'),
(1548,'COA-2026-075','Visitor\'s Chair (Stackable)',3,5,'2026-01-08',24760.29,5,'Manuel Ramos',5,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-09 09:00:00','2026-07-20 12:47:01'),
(1549,'COA-2026-076','Handheld Two-Way Radio',7,1,'2026-02-02',10237.60,4,'Juan Del Rosario',1,'Human Resource Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-02 09:00:00','2026-07-20 14:59:08'),
(1550,'COA-2024-138','Patrol Motorcycle',5,1,'2024-12-14',686168.52,7,NULL,1,'Treasury Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-12-15 09:00:00','2026-07-20 14:59:08'),
(1551,'COA-2025-137','Sprayer (Backpack, Motorized)',9,1,'2025-06-30',73819.50,12,'Manuel Pascual',1,'Municipal Health Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-06-30 09:00:00','2026-07-17 18:12:48'),
(1552,'COA-2017-165','Bulldozer',6,1,'2017-01-01',506518.33,5,'Teresa Villanueva',1,'Budget Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-04 09:00:00','2026-07-20 14:59:08'),
(1553,'COA-2026-077','Rice Thresher',9,1,'2026-01-04',153266.36,9,'Danilo Bautista',1,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2026-01-06 09:00:00','2026-07-20 14:59:08'),
(1554,'COA-2026-078','Refrigerator (2-Door)',1,1,'2026-03-28',41275.99,10,'Divina Santos',1,'Municipal Engineering Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-28 09:00:00','2026-07-20 14:59:08'),
(1555,'COA-2023-181','Bulldozer',6,1,'2023-10-31',1502197.65,13,'Elena Del Rosario',1,'Municipal Social Welfare and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-02 09:00:00','2026-07-17 18:12:48'),
(1556,'COA-2020-110','Multi-Purpose Van',5,1,'2020-09-18',1795237.97,16,'Ricardo Navarro',1,'Information and Communications Technology Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-20 09:00:00','2026-07-17 18:12:48'),
(1557,'COA-2022-149','Laptop Computer (Business Series)',2,1,'2022-02-14',77654.96,5,NULL,1,'Budget Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2022-02-14 09:00:00','2026-07-20 12:47:01'),
(1558,'COA-2020-111','Patrol Motorcycle',5,1,'2020-03-21',2093054.48,5,'Imelda Cruz',1,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-21 09:00:00','2026-07-20 14:59:08'),
(1559,'COA-2020-112','Concrete Mixer',6,1,'2020-09-27',1668341.55,9,'Carmen Santos',1,'Civil Registrar\'s Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-27 09:00:00','2026-07-20 14:59:08'),
(1560,'COA-2021-145','Dump Truck',5,1,'2021-12-17',1767117.35,16,'Norma Reyes',NULL,'Information and Communications Technology Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-18 09:00:00','2026-07-20 14:59:08'),
(1561,'COA-2025-138','Multi-Purpose Van',5,1,'2025-06-04',1330696.02,3,'Francisco Del Rosario',NULL,'Sangguniang Bayan Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-06-06 09:00:00','2026-07-17 18:12:48'),
(1562,'COA-2026-079','PABX Telephone System',7,1,'2026-01-07',10402.30,5,'Luz Reyes',1,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-10 09:00:00','2026-07-20 14:59:08'),
(1563,'COA-2025-139','Stretcher (Foldable)',8,1,'2025-08-22',113254.88,3,'Cecilia Domingo',1,'Sangguniang Bayan Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-23 09:00:00','2026-07-17 18:12:48'),
(1564,'COA-2020-113','Digital Blood Pressure Monitor',8,1,'2020-07-22',95983.74,2,'Gloria Rivera',1,'Office of the Vice Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-25 09:00:00','2026-07-20 14:59:08'),
(1565,'COA-2024-139','Electric Fan (Stand Type)',1,1,'2024-11-02',38583.47,12,NULL,NULL,'Municipal Health Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-03 09:00:00','2026-07-17 18:12:48'),
(1566,'COA-2018-159','Digital Blood Pressure Monitor',8,1,'2018-11-20',38741.07,14,'Norma Castillo',1,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-22 09:00:00','2026-07-17 18:12:48'),
(1567,'COA-2020-114','Patrol Motorcycle',5,1,'2020-11-22',584705.27,6,'Juan Flores',NULL,'Accounting Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-23 09:00:00','2026-07-20 14:59:08'),
(1568,'COA-2016-148','Typewriter (Manual)',4,1,'2016-09-01',13877.35,6,'Josefa Bautista',1,'Accounting Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-01 09:00:00','2026-07-20 14:59:08'),
(1569,'COA-2020-115','Oxygen Tank with Regulator',8,1,'2020-09-28',8278.93,4,'Corazon Gonzales',1,'Human Resource Management Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-28 09:00:00','2026-07-20 14:59:08'),
(1570,'COA-2022-150','Desktop Computer Set (Core i5)',2,1,'2022-06-27',23171.77,14,NULL,NULL,'Municipal Agriculture Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-30 09:00:00','2026-07-20 14:59:08'),
(1571,'COA-2025-140','Microwave Oven',1,1,'2025-12-26',12180.20,4,'Josefa Santos',NULL,'Human Resource Management Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2025-12-29 09:00:00','2026-07-20 14:59:08'),
(1572,'COA-2018-160','External Hard Drive 2TB',2,1,'2018-03-05',76193.33,13,'Antonio Del Rosario',NULL,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-06 09:00:00','2026-07-17 18:12:48'),
(1573,'COA-2022-151','Service Pick-up Truck',5,1,'2022-06-23',1942420.19,13,NULL,NULL,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2022-06-24 09:00:00','2026-07-17 18:12:48'),
(1574,'COA-2024-140','Inflatable Rescue Boat',10,1,'2024-04-24',72329.58,2,'Maria Mendoza',1,'Office of the Vice Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-25 09:00:00','2026-07-20 14:59:08'),
(1575,'COA-2017-166','Inflatable Rescue Boat',10,1,'2017-06-05',67166.43,8,NULL,NULL,'Assessor\'s Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-06 09:00:00','2026-07-20 14:59:08'),
(1576,'COA-2024-141','Vacuum Cleaner',1,1,'2024-08-29',5623.73,10,'Danilo Aguilar',1,'Municipal Engineering Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-01 09:00:00','2026-07-17 18:12:48'),
(1577,'COA-2018-161','Laminating Machine',4,1,'2018-12-20',4450.49,16,'Ricardo Gonzales',NULL,'Information and Communications Technology Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-23 09:00:00','2026-07-17 18:12:48'),
(1578,'COA-2016-149','Electric Fan (Stand Type)',1,1,'2016-07-01',37418.14,6,NULL,NULL,'Accounting Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-03 09:00:00','2026-07-20 14:59:08'),
(1579,'COA-2022-152','Service Vehicle (Sedan)',5,1,'2022-12-13',939112.45,8,'Gloria Reyes',1,'Assessor\'s Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2022-12-14 09:00:00','2026-07-20 14:59:08'),
(1580,'COA-2016-150','Photocopier Machine (Multi-function)',4,1,'2016-10-02',12545.78,12,'Rodrigo Castillo',NULL,'Municipal Health Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-04 09:00:00','2026-07-17 18:12:48'),
(1581,'COA-2025-141','Vacuum Cleaner',1,1,'2025-08-04',32997.00,8,'Divina Gonzales',1,'Assessor\'s Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-04 09:00:00','2026-07-17 18:12:48'),
(1582,'COA-2026-080','Typewriter (Manual)',4,1,'2026-04-22',39709.92,13,'Divina Gonzales',1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-23 09:00:00','2026-07-20 14:59:08'),
(1583,'COA-2017-167','Service Pick-up Truck',5,1,'2017-01-05',1989481.69,9,'Ernesto Castillo',NULL,'Civil Registrar\'s Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-07 09:00:00','2026-07-20 14:59:08'),
(1584,'COA-2020-116','Calculator (Desktop Printing)',4,1,'2020-07-02',7665.75,16,'Eduardo Aquino',NULL,'Information and Communications Technology Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-05 09:00:00','2026-07-20 14:59:08'),
(1585,'COA-2026-081','Inflatable Rescue Boat',10,1,'2026-02-10',33796.50,7,NULL,1,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-13 09:00:00','2026-07-17 18:12:48'),
(1586,'COA-2020-117','Megaphone (Bullhorn)',7,1,'2020-09-30',42908.60,5,'Pedro Del Rosario',1,'Budget Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2020-10-01 09:00:00','2026-07-20 12:47:01'),
(1587,'COA-2025-142','All-in-One Inkjet Printer',2,1,'2025-01-25',9063.08,15,'Rosa Del Rosario',NULL,'General Services Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2025-01-26 09:00:00','2026-07-20 14:59:08'),
(1588,'COA-2016-151','Bulldozer',6,1,'2016-02-10',618148.37,12,'Ernesto Garcia',1,'Municipal Health Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-12 09:00:00','2026-07-17 18:12:48'),
(1589,'COA-2023-182','Rescue Rope Kit',10,1,'2023-02-25',26266.33,15,'Pedro Aquino',NULL,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-02-27 09:00:00','2026-07-20 14:59:08'),
(1590,'COA-2022-153','Road Roller',6,1,'2022-08-16',2447468.24,4,NULL,1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-08-18 09:00:00','2026-07-20 14:59:08'),
(1591,'COA-2024-142','Typewriter (Manual)',4,1,'2024-06-29',39512.53,8,NULL,1,'Assessor\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-30 09:00:00','2026-07-17 18:12:48'),
(1592,'COA-2019-143','Service Vehicle (Sedan)',5,1,'2019-01-31',1995985.72,14,'Ricardo Aquino',1,'Municipal Agriculture Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-31 09:00:00','2026-07-20 14:59:08'),
(1593,'COA-2020-118','Oxygen Tank with Regulator',8,1,'2020-07-14',3631.75,5,'Manuel Salazar',NULL,'Budget Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-14 09:00:00','2026-07-20 14:59:08'),
(1594,'COA-2016-152','Concrete Mixer',6,1,'2016-11-24',2018966.37,12,'Rosa Mendoza',NULL,'Municipal Health Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-24 09:00:00','2026-07-20 14:59:08'),
(1595,'COA-2024-143','IP Desk Phone',7,1,'2024-06-27',21506.94,6,'Carlos Navarro',NULL,'Accounting Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-27 09:00:00','2026-07-20 14:59:08'),
(1596,'COA-2019-144','Motorcycle (Service Unit)',5,1,'2019-03-23',1453445.93,3,'Divina Dela Cruz',1,'Sangguniang Bayan Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-25 09:00:00','2026-07-17 18:12:48'),
(1597,'COA-2026-082','Electric Kettle',1,1,'2026-04-20',45971.64,9,'Eduardo Aquino',1,'Civil Registrar\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-22 09:00:00','2026-07-20 14:59:08'),
(1598,'COA-2024-144','Laptop Computer (Business Series)',2,1,'2024-04-08',51843.82,2,'Ernesto Torres',1,'Office of the Vice Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-10 09:00:00','2026-07-17 18:12:48'),
(1599,'COA-2023-183','Handheld Two-Way Radio',7,1,'2023-10-17',20344.56,1,'Ricardo Garcia',NULL,'Office of the Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-19 09:00:00','2026-07-17 18:12:48'),
(1600,'COA-2020-119','Water Dispenser (Hot & Cold)',1,1,'2020-11-20',23023.42,16,'Ricardo Marquez',1,'Information and Communications Technology Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-11-22 09:00:00','2026-07-17 18:12:48'),
(1601,'COA-2017-168','Ambulance Unit',5,1,'2017-01-04',1895784.12,14,'Leonora Flores',1,'Municipal Agriculture Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-07 09:00:00','2026-07-20 14:59:08'),
(1602,'COA-2019-145','Metal Detector (Handheld)',10,1,'2019-03-05',10663.27,9,'Pedro Torres',NULL,'Civil Registrar\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-06 09:00:00','2026-07-20 14:59:08'),
(1603,'COA-2021-146','Steel Locker Cabinet',3,5,'2021-04-08',10901.93,15,NULL,5,'General Services Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-08 09:00:00','2026-07-17 18:12:48'),
(1604,'COA-2025-143','Service Vehicle (Sedan)',5,1,'2025-01-26',1278417.57,14,NULL,1,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-29 09:00:00','2026-07-20 14:59:08'),
(1605,'COA-2019-146','Typewriter (Manual)',4,1,'2019-05-12',5552.93,6,'Cecilia Flores',1,'Accounting Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-14 09:00:00','2026-07-20 14:59:08'),
(1606,'COA-2021-147','Concrete Mixer',6,1,'2021-08-14',1457855.36,7,'Eduardo Dela Cruz',1,'Treasury Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-14 09:00:00','2026-07-17 18:12:48'),
(1607,'COA-2019-147','CCTV DVR/NVR Unit',7,1,'2019-02-24',22373.45,2,'Teresa Ocampo',1,'Office of the Vice Mayor - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-02-26 09:00:00','2026-07-17 18:12:48'),
(1608,'COA-2025-144','Laminating Machine',4,1,'2025-10-21',41800.93,17,'Norma Ramos',1,'Disaster Risk Reduction and Management Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2025-10-21 09:00:00','2026-07-20 14:59:08'),
(1609,'COA-2021-148','Chainsaw (Rescue Type)',10,1,'2021-05-07',9221.69,8,'Maria Villanueva',1,'Assessor\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-10 09:00:00','2026-07-17 18:12:48'),
(1610,'COA-2019-148','Rice Thresher',9,2,'2019-02-03',12541.98,9,'Jose Gonzales',NULL,'Civil Registrar\'s Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-03 09:00:00','2026-07-20 14:59:08'),
(1611,'COA-2024-145','Visitor\'s Chair (Stackable)',3,2,'2024-06-19',16032.53,13,'Divina Santos',2,'Municipal Social Welfare and Development Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-20 09:00:00','2026-07-20 14:59:08'),
(1612,'COA-2017-169','Water Cooler/Dispenser',1,1,'2017-09-02',27457.34,2,'Eduardo Bautista',NULL,'Office of the Vice Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-03 09:00:00','2026-07-20 14:59:08'),
(1613,'COA-2018-162','Electric Kettle',1,1,'2018-08-25',24124.62,10,NULL,NULL,'Municipal Engineering Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-26 09:00:00','2026-07-17 18:12:48'),
(1614,'COA-2016-153','Fax Machine',4,1,'2016-04-20',32948.91,7,'Carlos Dela Cruz',1,'Treasury Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-04-20 09:00:00','2026-07-20 14:59:08'),
(1615,'COA-2026-083','CCTV Camera (Outdoor)',7,1,'2026-03-21',29800.86,16,'Corazon Dela Cruz',NULL,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-24 09:00:00','2026-07-17 18:12:48'),
(1616,'COA-2021-149','Air Conditioning Unit (1.5HP Split Type)',1,1,'2021-04-12',32563.66,13,'Imelda Mendoza',1,'Municipal Social Welfare and Development Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-15 09:00:00','2026-07-20 14:59:08'),
(1617,'COA-2025-145','Backhoe Loader',6,1,'2025-07-06',2754951.14,11,'Eduardo Garcia',1,'Municipal Planning and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-08 09:00:00','2026-07-20 14:59:08'),
(1618,'COA-2023-184','External Hard Drive 2TB',2,1,'2023-08-28',9319.68,13,'Rosa Reyes',NULL,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-28 09:00:00','2026-07-20 14:59:08'),
(1619,'COA-2024-146','Emergency Light Tower',10,1,'2024-08-06',49334.23,6,'Imelda Navarro',1,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-07 09:00:00','2026-07-17 18:12:48'),
(1620,'COA-2021-150','Paper Shredder (Heavy Duty)',4,1,'2021-03-14',31367.55,8,NULL,1,'Assessor\'s Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-16 09:00:00','2026-07-20 14:59:08'),
(1621,'COA-2024-147','Air Conditioning Unit (1.5HP Split Type)',1,1,'2024-01-19',53555.00,7,'Ernesto Flores',1,'Treasury Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-21 09:00:00','2026-07-20 14:59:08'),
(1622,'COA-2016-154','PABX Telephone System',7,1,'2016-04-19',27949.61,15,'Antonio Gonzales',NULL,'General Services Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-04-20 09:00:00','2026-07-20 14:59:08'),
(1623,'COA-2024-148','Water Pump (Irrigation)',9,1,'2024-04-29',146769.12,17,'Divina Marquez',NULL,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-29 09:00:00','2026-07-17 18:12:48'),
(1624,'COA-2023-185','Base Radio Station',7,1,'2023-06-09',31306.54,9,'Rodrigo Rivera',1,'Civil Registrar\'s Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-09 09:00:00','2026-07-17 18:12:48'),
(1625,'COA-2026-084','Emergency Light Tower',10,1,'2026-02-08',62826.55,5,'Juan Torres',1,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-09 09:00:00','2026-07-20 14:59:08'),
(1626,'COA-2025-146','Electric Fan (Stand Type)',1,1,'2025-11-12',13188.32,15,'Cecilia Reyes',1,'General Services Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-13 09:00:00','2026-07-20 14:59:08'),
(1627,'COA-2022-154','Swivel Office Chair',3,1,'2022-03-03',23522.35,14,'Antonio Dela Cruz',NULL,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-03 09:00:00','2026-07-17 18:12:48'),
(1628,'COA-2016-155','Weighing Scale (Digital)',8,1,'2016-12-29',51145.38,9,'Gloria Navarro',NULL,'Civil Registrar\'s Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-31 09:00:00','2026-07-20 14:59:08'),
(1629,'COA-2022-155','Executive Office Desk',3,5,'2022-04-02',4776.97,1,'Corazon Bautista',NULL,'Office of the Mayor - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-04-02 09:00:00','2026-07-17 18:12:48'),
(1630,'COA-2019-149','Binding Machine',4,1,'2019-02-23',16537.21,9,'Manuel Fernandez',1,'Civil Registrar\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2019-02-23 09:00:00','2026-07-17 18:12:48'),
(1631,'COA-2025-147','Water Dispenser (Hot & Cold)',1,1,'2025-02-01',18158.47,10,'Carmen Torres',1,'Municipal Engineering Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-02-02 09:00:00','2026-07-20 14:59:08'),
(1632,'COA-2022-156','Microwave Oven',1,1,'2022-03-08',32418.50,6,'Alfredo Marquez',1,'Accounting Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-03-11 09:00:00','2026-07-17 18:12:48'),
(1633,'COA-2019-150','Multi-Purpose Van',5,1,'2019-12-12',839035.31,2,'Ramon Rivera',1,'Office of the Vice Mayor - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2019-12-13 09:00:00','2026-07-20 14:59:08'),
(1634,'COA-2025-148','CCTV Camera (Outdoor)',7,1,'2025-06-04',25738.33,9,'Leonora Marquez',NULL,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-06-04 09:00:00','2026-07-17 18:12:48'),
(1635,'COA-2018-163','Fax Machine',4,1,'2018-08-03',5383.30,5,'Francisco Cruz',1,'Budget Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-03 09:00:00','2026-07-20 12:47:01'),
(1636,'COA-2017-170','Digital Blood Pressure Monitor',8,1,'2017-07-06',114230.93,6,'Ricardo Domingo',1,'Accounting Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-07 09:00:00','2026-07-17 18:12:48'),
(1637,'COA-2017-171','Rescue Rope Kit',10,1,'2017-12-25',85006.25,14,'Eduardo Cruz',1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-28 09:00:00','2026-07-17 18:12:48'),
(1638,'COA-2025-149','Sprayer (Backpack, Motorized)',9,5,'2025-09-13',94356.53,16,'Francisco Cruz',5,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-14 09:00:00','2026-07-20 14:59:08'),
(1639,'COA-2026-085','Seedling Tray Set',9,1,'2026-01-14',20381.46,9,'Ricardo Ocampo',1,'Civil Registrar\'s Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2026-01-16 09:00:00','2026-07-17 18:12:48'),
(1640,'COA-2016-156','Dump Truck',5,1,'2016-07-22',2163055.28,10,'Gloria Domingo',1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-25 09:00:00','2026-07-20 14:59:08'),
(1641,'COA-2025-150','Binding Machine',4,1,'2025-10-06',48327.53,2,'Carlos Villanueva',1,'Office of the Vice Mayor - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-10-08 09:00:00','2026-07-17 18:12:48'),
(1642,'COA-2017-172','Hand Tractor',9,5,'2017-06-26',111676.42,16,'Antonio Del Rosario',5,'Information and Communications Technology Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2017-06-28 09:00:00','2026-07-20 14:59:08'),
(1643,'COA-2018-164','Air Conditioning Unit (1.5HP Split Type)',1,1,'2018-01-18',20183.76,17,'Eduardo Salazar',1,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-01-18 09:00:00','2026-07-20 14:59:08'),
(1644,'COA-2023-186','Bookshelf (Wooden, 5-Tier)',3,2,'2023-04-12',15509.81,2,NULL,2,'Office of the Vice Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-13 09:00:00','2026-07-17 18:12:48'),
(1645,'COA-2021-151','Base Radio Station',7,1,'2021-05-21',34702.07,11,'Norma Fernandez',1,'Municipal Planning and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-24 09:00:00','2026-07-17 18:12:48'),
(1646,'COA-2018-165','Steel Filing Cabinet (4-Drawer)',3,1,'2018-07-12',14121.94,11,'Leonora Domingo',1,'Municipal Planning and Development Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-07-13 09:00:00','2026-07-17 18:12:48'),
(1647,'COA-2019-151','Desktop Computer Set (Core i5)',2,1,'2019-12-03',24608.95,16,'Eduardo Del Rosario',NULL,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-06 09:00:00','2026-07-17 18:12:48'),
(1648,'COA-2021-152','External Hard Drive 2TB',2,1,'2021-10-13',22083.35,7,'Carlos Villanueva',1,'Treasury Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-10-13 09:00:00','2026-07-20 14:59:08'),
(1649,'COA-2020-120','Service Vehicle (Sedan)',5,1,'2020-11-01',1226880.05,16,NULL,1,'Information and Communications Technology Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-01 09:00:00','2026-07-20 14:59:08'),
(1650,'COA-2024-149','Concrete Mixer',6,1,'2024-09-19',2083657.32,3,'Rodrigo Reyes',NULL,'Sangguniang Bayan Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-22 09:00:00','2026-07-20 14:59:08'),
(1651,'COA-2016-157','Water Pump (Irrigation)',9,1,'2016-11-17',71192.46,12,NULL,1,'Municipal Health Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-20 09:00:00','2026-07-17 18:12:48'),
(1652,'COA-2019-152','External Hard Drive 2TB',2,1,'2019-08-07',27324.62,4,'Corazon Domingo',NULL,'Human Resource Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2019-08-08 09:00:00','2026-07-20 14:59:08'),
(1653,'COA-2026-086','Electric Fan (Stand Type)',1,1,'2026-01-02',40133.29,8,'Luz Bautista',NULL,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-03 09:00:00','2026-07-17 18:12:48'),
(1654,'COA-2025-151','Executive Office Desk',3,1,'2025-01-07',16973.58,3,'Rosa Ocampo',1,'Sangguniang Bayan Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-07 09:00:00','2026-07-20 14:59:08'),
(1655,'COA-2021-153','Electric Fan (Stand Type)',1,1,'2021-12-27',10456.47,15,'Corazon Marquez',NULL,'General Services Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-28 09:00:00','2026-07-17 18:12:48'),
(1656,'COA-2019-153','Fax Machine',4,1,'2019-11-04',11193.37,8,'Carlos Cruz',1,'Assessor\'s Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-05 09:00:00','2026-07-20 14:59:08'),
(1657,'COA-2016-158','CCTV Camera (Outdoor)',7,1,'2016-06-23',33092.96,16,'Josefa Reyes',1,'Information and Communications Technology Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-25 09:00:00','2026-07-20 14:59:08'),
(1658,'COA-2016-159','Service Vehicle (Sedan)',5,1,'2016-11-19',799461.28,8,NULL,1,'Assessor\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-19 09:00:00','2026-07-20 14:59:08'),
(1659,'COA-2024-150','Water Tanker Truck',6,1,'2024-12-22',1036761.15,6,'Ana Cruz',1,'Accounting Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-12-25 09:00:00','2026-07-20 14:59:08'),
(1660,'COA-2016-160','Bookshelf (Wooden, 5-Tier)',3,1,'2016-03-15',17296.61,5,'Juan Salazar',1,'Budget Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-18 09:00:00','2026-07-20 12:47:01'),
(1661,'COA-2026-087','Farm Tool Kit',9,1,'2026-04-20',17607.34,5,'Luz Domingo',1,'Budget Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-23 09:00:00','2026-07-20 12:47:01'),
(1662,'COA-2017-173','Megaphone (Bullhorn)',7,1,'2017-06-25',19816.42,14,'Danilo Navarro',1,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-28 09:00:00','2026-07-20 14:59:08'),
(1663,'COA-2017-174','Multi-Purpose Van',5,1,'2017-06-15',1300783.17,1,'Francisco Dela Cruz',1,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-16 09:00:00','2026-07-20 14:59:08'),
(1664,'COA-2018-166','PABX Telephone System',7,1,'2018-09-04',37742.49,13,'Pedro Ocampo',1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-04 09:00:00','2026-07-17 18:12:48'),
(1665,'COA-2025-152','All-in-One Inkjet Printer',2,1,'2025-08-21',52758.05,1,'Rosa Reyes',1,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-22 09:00:00','2026-07-20 14:59:08'),
(1666,'COA-2022-157','Thermal Scanner',8,1,'2022-05-17',83989.49,12,'Leonora Bautista',1,'Municipal Health Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-20 09:00:00','2026-07-17 18:12:48'),
(1667,'COA-2026-088','Thermal Scanner',8,1,'2026-04-14',112231.70,12,'Ramon Ramos',1,'Municipal Health Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-16 09:00:00','2026-07-17 18:12:48'),
(1668,'COA-2021-154','Backhoe Loader',6,1,'2021-10-05',704413.81,8,'Cecilia Bautista',NULL,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-10-08 09:00:00','2026-07-17 18:12:48'),
(1669,'COA-2020-121','Road Roller',6,1,'2020-07-21',2820824.10,13,'Imelda Aquino',1,'Municipal Social Welfare and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-22 09:00:00','2026-07-20 14:59:08'),
(1670,'COA-2025-153','PABX Telephone System',7,1,'2025-02-03',38215.15,4,'Teresa Dela Cruz',NULL,'Human Resource Management Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-02-03 09:00:00','2026-07-17 18:12:48'),
(1671,'COA-2017-175','Base Radio Station',7,1,'2017-06-20',17516.08,1,NULL,1,'Office of the Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-21 09:00:00','2026-07-17 18:12:48'),
(1672,'COA-2021-155','Laptop Computer (Business Series)',2,1,'2021-07-28',31650.60,14,'Ricardo Pascual',1,'Municipal Agriculture Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-07-29 09:00:00','2026-07-17 18:12:48'),
(1673,'COA-2019-154','Bulletin Board (Cork, Framed)',4,1,'2019-06-13',38164.39,11,'Manuel Ramos',NULL,'Municipal Planning and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-15 09:00:00','2026-07-17 18:12:48'),
(1674,'COA-2017-176','Grass Cutter (Riding Type)',6,1,'2017-05-19',3010691.11,15,'Rodrigo Rivera',NULL,'General Services Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-21 09:00:00','2026-07-17 18:12:48'),
(1675,'COA-2020-122','Handheld Two-Way Radio',7,1,'2020-05-09',26033.48,11,'Antonio Marquez',NULL,'Municipal Planning and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-11 09:00:00','2026-07-17 18:12:48'),
(1676,'COA-2024-151','Oxygen Tank with Regulator',8,1,'2024-08-28',116512.45,2,NULL,NULL,'Office of the Vice Mayor - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-29 09:00:00','2026-07-20 14:59:08'),
(1677,'COA-2017-177','Desktop Computer Set (Core i5)',2,1,'2017-11-02',54070.66,6,'Elena Torres',1,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-04 09:00:00','2026-07-17 18:12:48'),
(1678,'COA-2019-155','Binding Machine',4,1,'2019-03-30',5474.92,13,NULL,1,'Municipal Social Welfare and Development Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-02 09:00:00','2026-07-20 14:59:08'),
(1679,'COA-2017-178','Partition Divider Panel',3,2,'2017-11-08',25814.36,9,'Danilo Mendoza',2,'Civil Registrar\'s Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2017-11-10 09:00:00','2026-07-20 14:59:08'),
(1680,'COA-2016-161','Ambulance Unit',5,1,'2016-09-24',1529482.84,1,'Divina Mendoza',1,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-09-27 09:00:00','2026-07-20 14:59:08'),
(1681,'COA-2024-152','Partition Divider Panel',3,1,'2024-12-19',23172.74,1,NULL,NULL,'Office of the Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-12-20 09:00:00','2026-07-20 14:59:08'),
(1682,'COA-2018-167','CCTV Camera (Outdoor)',7,1,'2018-04-06',43274.43,3,'Juan Marquez',NULL,'Sangguniang Bayan Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-06 09:00:00','2026-07-20 14:59:08'),
(1683,'COA-2021-156','Partition Divider Panel',3,2,'2021-07-11',13711.91,5,'Jose Aguilar',NULL,'Budget Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2021-07-12 09:00:00','2026-07-20 12:47:01'),
(1684,'COA-2022-158','Electric Kettle',1,1,'2022-04-06',5248.90,7,'Maria Castillo',1,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-04-08 09:00:00','2026-07-17 18:12:48'),
(1685,'COA-2024-153','Microwave Oven',1,1,'2024-11-14',40716.04,16,'Josefa Ramos',1,'Information and Communications Technology Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-14 09:00:00','2026-07-20 14:59:08'),
(1686,'COA-2020-123','CCTV Camera (Outdoor)',7,1,'2020-02-29',41855.16,5,'Teresa Mendoza',1,'Budget Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-02 09:00:00','2026-07-20 12:47:01'),
(1687,'COA-2020-124','CCTV DVR/NVR Unit',7,1,'2020-08-13',5516.39,9,'Ramon Castillo',NULL,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-15 09:00:00','2026-07-20 14:59:08'),
(1688,'COA-2024-154','Chainsaw (Rescue Type)',10,1,'2024-05-24',79993.79,16,'Alfredo Cruz',NULL,'Information and Communications Technology Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2024-05-24 09:00:00','2026-07-20 14:59:08'),
(1689,'COA-2017-179','Emergency Light Tower',10,1,'2017-08-08',40775.97,7,NULL,NULL,'Treasury Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-10 09:00:00','2026-07-17 18:12:48'),
(1690,'COA-2024-155','UPS (Uninterruptible Power Supply)',2,1,'2024-01-22',52686.46,6,NULL,1,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-25 09:00:00','2026-07-20 14:59:08'),
(1691,'COA-2018-168','Backhoe Loader',6,1,'2018-10-27',361638.75,8,'Imelda Pascual',NULL,'Assessor\'s Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-29 09:00:00','2026-07-20 14:59:08'),
(1692,'COA-2021-157','Water Pump (Irrigation)',9,1,'2021-07-31',149414.47,10,NULL,1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-01 09:00:00','2026-07-17 18:12:48'),
(1693,'COA-2017-180','Rice Thresher',9,1,'2017-08-01',82969.34,17,'Rodrigo Salazar',1,'Disaster Risk Reduction and Management Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2017-08-04 09:00:00','2026-07-20 14:59:08'),
(1694,'COA-2022-159','Laminating Machine',4,1,'2022-06-15',27850.47,9,'Eduardo Cruz',1,'Civil Registrar\'s Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-18 09:00:00','2026-07-20 14:59:08'),
(1695,'COA-2022-160','Autoclave Sterilizer',8,1,'2022-05-12',24346.53,9,'Elena Dela Cruz',1,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-13 09:00:00','2026-07-17 18:12:48'),
(1696,'COA-2020-125','Fire Extinguisher (10lbs)',10,1,'2020-09-04',37729.77,5,'Ana Aguilar',NULL,'Budget Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-07 09:00:00','2026-07-20 12:47:01'),
(1697,'COA-2019-156','Water Pump (Irrigation)',9,1,'2019-08-13',160314.51,13,'Rosa Ramos',1,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-14 09:00:00','2026-07-20 14:59:08'),
(1698,'COA-2025-154','Base Radio Station',7,1,'2025-08-06',14874.73,17,'Jose Aguilar',NULL,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-08 09:00:00','2026-07-17 18:12:48'),
(1699,'COA-2019-157','Hand Tractor',9,1,'2019-04-27',144995.72,16,'Carlos Rivera',NULL,'Information and Communications Technology Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-30 09:00:00','2026-07-20 14:59:08'),
(1700,'COA-2021-158','Electric Fan (Stand Type)',1,1,'2021-01-27',52812.40,3,'Maria Cruz',1,'Sangguniang Bayan Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2021-01-29 09:00:00','2026-07-20 14:59:08'),
(1701,'COA-2016-162','Microwave Oven',1,1,'2016-05-04',41702.15,8,'Imelda Navarro',1,'Assessor\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-05-06 09:00:00','2026-07-20 14:59:08'),
(1702,'COA-2017-181','Emergency Light Tower',10,1,'2017-07-06',27364.45,16,NULL,1,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-09 09:00:00','2026-07-17 18:12:48'),
(1703,'COA-2018-169','Electric Kettle',1,1,'2018-04-18',42059.33,15,'Danilo Salazar',1,'General Services Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-20 09:00:00','2026-07-20 14:59:08'),
(1704,'COA-2023-187','Fire Extinguisher (10lbs)',10,1,'2023-08-04',84609.22,9,'Rodrigo Gonzales',1,'Civil Registrar\'s Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-07 09:00:00','2026-07-20 14:59:08'),
(1705,'COA-2017-182','Electric Kettle',1,1,'2017-01-03',50345.75,8,'Ernesto Garcia',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-06 09:00:00','2026-07-20 14:59:08'),
(1706,'COA-2017-183','Water Cooler/Dispenser',1,1,'2017-01-29',37411.86,8,'Cecilia Aguilar',1,'Assessor\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-01 09:00:00','2026-07-20 14:59:08'),
(1707,'COA-2024-156','Service Pick-up Truck',5,1,'2024-02-03',802566.53,17,'Ernesto Ocampo',1,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-02-05 09:00:00','2026-07-17 18:12:48'),
(1708,'COA-2022-161','Ambulance Unit',5,1,'2022-05-25',728553.63,4,'Elena Mendoza',1,'Human Resource Management Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-05-27 09:00:00','2026-07-17 18:12:48'),
(1709,'COA-2017-184','Inflatable Rescue Boat',10,1,'2017-11-09',41059.07,9,'Gloria Rivera',1,'Civil Registrar\'s Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-12 09:00:00','2026-07-20 14:59:08'),
(1710,'COA-2023-188','Metal Detector (Handheld)',10,1,'2023-05-15',87072.51,7,'Jose Rivera',1,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-18 09:00:00','2026-07-17 18:12:48'),
(1711,'COA-2020-126','Grass Cutter (Riding Type)',6,1,'2020-08-24',1913964.20,10,'Gloria Aguilar',1,'Municipal Engineering Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-24 09:00:00','2026-07-20 14:59:08'),
(1712,'COA-2017-185','Rescue Rope Kit',10,1,'2017-09-12',23203.91,1,'Eduardo Reyes',1,'Office of the Mayor - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-14 09:00:00','2026-07-17 18:12:48'),
(1713,'COA-2016-163','Farm Tool Kit',9,5,'2016-08-15',53020.25,15,'Francisco Navarro',5,'General Services Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-08-15 09:00:00','2026-07-17 18:12:48'),
(1714,'COA-2025-155','Seedling Tray Set',9,5,'2025-03-06',113691.64,3,'Francisco Ocampo',5,'Sangguniang Bayan Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-09 09:00:00','2026-07-17 18:12:48'),
(1715,'COA-2021-159','Motorcycle (Service Unit)',5,1,'2021-09-19',1783684.79,12,'Rosa Domingo',1,'Municipal Health Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-09-21 09:00:00','2026-07-17 18:12:48'),
(1716,'COA-2020-127','Refrigerator (2-Door)',1,1,'2020-06-20',10424.23,16,'Imelda Bautista',1,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2020-06-20 09:00:00','2026-07-20 14:59:08'),
(1717,'COA-2023-189','Steel Locker Cabinet',3,1,'2023-03-21',14887.93,17,'Divina Dela Cruz',NULL,'Disaster Risk Reduction and Management Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-03-24 09:00:00','2026-07-17 18:12:48'),
(1718,'COA-2025-156','Fire Extinguisher (10lbs)',10,1,'2025-10-16',6378.00,2,'Elena Salazar',1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-19 09:00:00','2026-07-17 18:12:48'),
(1719,'COA-2023-190','Water Pump (Irrigation)',9,5,'2023-06-01',162724.21,14,NULL,5,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-04 09:00:00','2026-07-17 18:12:48'),
(1720,'COA-2019-158','Laminating Machine',4,1,'2019-10-17',45812.05,7,'Josefa Pascual',1,'Treasury Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-19 09:00:00','2026-07-20 14:59:08'),
(1721,'COA-2020-128','Electric Fan (Stand Type)',1,1,'2020-12-07',21267.51,11,'Ricardo Salazar',NULL,'Municipal Planning and Development Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-12-09 09:00:00','2026-07-20 14:59:08'),
(1722,'COA-2021-160','Motorcycle (Service Unit)',5,1,'2021-09-16',816164.01,12,NULL,1,'Municipal Health Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-09-16 09:00:00','2026-07-20 14:59:08'),
(1723,'COA-2018-170','24-Port Network Switch',2,1,'2018-07-18',73364.88,5,'Cecilia Pascual',NULL,'Budget Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-18 09:00:00','2026-07-20 14:59:08'),
(1724,'COA-2022-162','Thermal Scanner',8,1,'2022-12-05',65220.63,15,NULL,1,'General Services Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-07 09:00:00','2026-07-20 14:59:08'),
(1725,'COA-2021-161','Motorcycle (Service Unit)',5,1,'2021-04-21',1867859.19,14,'Ernesto Flores',1,'Municipal Agriculture Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-21 09:00:00','2026-07-17 18:12:48'),
(1726,'COA-2018-171','Concrete Mixer',6,1,'2018-06-14',1771036.00,16,'Leonora Bautista',1,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-06-16 09:00:00','2026-07-17 18:12:48'),
(1727,'COA-2018-172','Steel Filing Cabinet (4-Drawer)',3,5,'2018-08-14',11745.88,15,'Norma Torres',NULL,'General Services Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-15 09:00:00','2026-07-20 14:59:08'),
(1728,'COA-2018-173','Swivel Office Chair',3,1,'2018-07-17',3624.60,8,NULL,1,'Assessor\'s Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-07-19 09:00:00','2026-07-17 18:12:48'),
(1729,'COA-2024-157','Inflatable Rescue Boat',10,1,'2024-12-08',4228.84,14,'Carlos Villanueva',NULL,'Municipal Agriculture Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-12-11 09:00:00','2026-07-20 14:59:08'),
(1730,'COA-2022-163','Life Vest',10,1,'2022-02-09',62478.06,12,NULL,1,'Municipal Health Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2022-02-12 09:00:00','2026-07-17 18:12:48'),
(1731,'COA-2016-164','Steel Filing Cabinet (4-Drawer)',3,2,'2016-11-11',16329.78,6,'Alfredo Villanueva',2,'Accounting Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-11 09:00:00','2026-07-20 14:59:08'),
(1732,'COA-2025-157','Chainsaw (Rescue Type)',10,1,'2025-03-01',20915.80,9,'Francisco Villanueva',1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-03 09:00:00','2026-07-20 14:59:08'),
(1733,'COA-2024-158','Photocopier Machine (Multi-function)',4,1,'2024-08-22',53338.28,7,'Leonora Fernandez',1,'Treasury Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-08-23 09:00:00','2026-07-20 14:59:08'),
(1734,'COA-2020-129','LCD/LED Monitor 24\"',2,1,'2020-08-29',42288.75,7,'Norma Domingo',NULL,'Treasury Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-09-01 09:00:00','2026-07-20 14:59:08'),
(1735,'COA-2025-158','Service Vehicle (Sedan)',5,1,'2025-02-05',685247.74,6,'Pedro Garcia',1,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-02-07 09:00:00','2026-07-20 14:59:08'),
(1736,'COA-2025-159','PABX Telephone System',7,1,'2025-12-28',23249.44,8,'Juan Bautista',1,'Assessor\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-31 09:00:00','2026-07-17 18:12:48'),
(1737,'COA-2016-165','Motorcycle (Service Unit)',5,1,'2016-04-20',737358.02,10,'Leonora Aquino',NULL,'Municipal Engineering Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-04-23 09:00:00','2026-07-20 14:59:08'),
(1738,'COA-2017-186','CCTV Camera (Outdoor)',7,1,'2017-03-26',18808.53,2,'Pedro Domingo',NULL,'Office of the Vice Mayor - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-03-28 09:00:00','2026-07-17 18:12:48'),
(1739,'COA-2019-159','CCTV Camera (Outdoor)',7,1,'2019-12-29',34712.18,11,'Josefa Del Rosario',1,'Municipal Planning and Development Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2019-12-29 09:00:00','2026-07-20 14:59:08'),
(1740,'COA-2024-159','Electric Kettle',1,1,'2024-05-01',20521.94,6,'Carlos Ramos',1,'Accounting Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-01 09:00:00','2026-07-17 18:12:48'),
(1741,'COA-2019-160','Bulletin Board (Cork, Framed)',4,1,'2019-05-16',49811.75,1,NULL,1,'Office of the Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-18 09:00:00','2026-07-17 18:12:48'),
(1742,'COA-2017-187','Multi-Purpose Van',5,1,'2017-09-01',612391.24,7,'Divina Navarro',1,'Treasury Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-09-04 09:00:00','2026-07-20 14:59:08'),
(1743,'COA-2016-166','Electric Kettle',1,1,'2016-02-27',17484.28,10,'Rodrigo Aguilar',1,'Municipal Engineering Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-01 09:00:00','2026-07-20 14:59:08'),
(1744,'COA-2018-174','Hand Tractor',9,1,'2018-09-23',39882.02,16,'Jose Santos',NULL,'Information and Communications Technology Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2018-09-23 09:00:00','2026-07-17 18:12:48'),
(1745,'COA-2017-188','Hand Tractor',9,5,'2017-02-02',121999.98,15,'Antonio Aguilar',5,'General Services Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-02-05 09:00:00','2026-07-20 14:59:08'),
(1746,'COA-2025-160','Vacuum Cleaner',1,1,'2025-09-07',45653.33,5,'Elena Ocampo',1,'Budget Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2025-09-08 09:00:00','2026-07-20 12:47:01'),
(1747,'COA-2021-162','Vacuum Cleaner',1,1,'2021-08-19',48399.63,6,NULL,1,'Accounting Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-20 09:00:00','2026-07-17 18:12:48'),
(1748,'COA-2024-160','Laser Printer (Monochrome)',2,1,'2024-11-02',9130.06,10,'Maria Bautista',1,'Municipal Engineering Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2024-11-04 09:00:00','2026-07-17 18:12:48'),
(1749,'COA-2020-130','All-in-One Inkjet Printer',2,1,'2020-10-04',23052.92,13,'Pedro Garcia',NULL,'Municipal Social Welfare and Development Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-04 09:00:00','2026-07-20 14:59:08'),
(1750,'COA-2016-167','Bookshelf (Wooden, 5-Tier)',3,2,'2016-07-12',4947.66,6,'Imelda Ocampo',2,'Accounting Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-14 09:00:00','2026-07-20 14:59:08'),
(1751,'COA-2018-175','Rescue Rope Kit',10,1,'2018-02-27',61682.04,4,'Ricardo Domingo',NULL,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-27 09:00:00','2026-07-17 18:12:48'),
(1752,'COA-2017-189','Service Pick-up Truck',5,1,'2017-06-01',982488.73,11,'Luz Villanueva',1,'Municipal Planning and Development Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-04 09:00:00','2026-07-20 14:59:08'),
(1753,'COA-2024-161','Bookshelf (Wooden, 5-Tier)',3,1,'2024-03-07',12918.71,2,'Imelda Salazar',1,'Office of the Vice Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-08 09:00:00','2026-07-17 18:12:48'),
(1754,'COA-2025-161','Concrete Mixer',6,1,'2025-05-12',612528.20,13,'Manuel Domingo',NULL,'Municipal Social Welfare and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-15 09:00:00','2026-07-20 14:59:08'),
(1755,'COA-2025-162','Generator Set (25 kVA)',6,1,'2025-10-13',1806056.48,8,'Teresa Aguilar',1,'Assessor\'s Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-10-15 09:00:00','2026-07-20 14:59:08'),
(1756,'COA-2019-161','Water Tanker Truck',6,1,'2019-03-27',2565745.89,6,NULL,1,'Accounting Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-27 09:00:00','2026-07-17 18:12:48'),
(1757,'COA-2024-162','CCTV DVR/NVR Unit',7,1,'2024-07-17',39929.58,5,'Romeo Castillo',1,'Budget Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-18 09:00:00','2026-07-20 14:59:08'),
(1758,'COA-2019-162','Ambulance Unit',5,1,'2019-10-19',593143.38,4,'Leonora Fernandez',1,'Human Resource Management Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-19 09:00:00','2026-07-20 14:59:08'),
(1759,'COA-2022-164','Multi-Purpose Van',5,1,'2022-02-24',1325369.76,14,'Imelda Navarro',1,'Municipal Agriculture Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-25 09:00:00','2026-07-17 18:12:48'),
(1760,'COA-2020-131','Paper Shredder (Heavy Duty)',4,1,'2020-08-27',24978.05,3,'Ricardo Santos',1,'Sangguniang Bayan Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-28 09:00:00','2026-07-20 14:59:08'),
(1761,'COA-2021-163','Oxygen Tank with Regulator',8,1,'2021-04-25',46475.44,7,'Rosa Dela Cruz',1,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-27 09:00:00','2026-07-20 14:59:08'),
(1762,'COA-2017-190','Service Pick-up Truck',5,1,'2017-04-27',2163621.30,7,NULL,1,'Treasury Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-04-28 09:00:00','2026-07-17 18:12:48'),
(1763,'COA-2024-163','Motorcycle (Service Unit)',5,1,'2024-05-24',2185116.32,5,'Manuel Marquez',1,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-24 09:00:00','2026-07-20 14:59:08'),
(1764,'COA-2016-168','Rescue Rope Kit',10,1,'2016-02-16',38773.28,10,'Ricardo Del Rosario',1,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-17 09:00:00','2026-07-17 18:12:48'),
(1765,'COA-2022-165','Autoclave Sterilizer',8,1,'2022-12-16',55002.49,3,'Teresa Del Rosario',1,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-17 09:00:00','2026-07-17 18:12:48'),
(1766,'COA-2017-191','Inflatable Rescue Boat',10,1,'2017-04-10',74174.57,1,'Corazon Ramos',1,'Office of the Mayor - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-04-10 09:00:00','2026-07-17 18:12:48'),
(1767,'COA-2021-164','Dump Truck',5,1,'2021-05-04',1183708.60,7,'Divina Torres',NULL,'Treasury Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-05 09:00:00','2026-07-20 14:59:08'),
(1768,'COA-2025-163','Vacuum Cleaner',1,1,'2025-09-12',28415.25,3,'Jose Ramos',NULL,'Sangguniang Bayan Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-14 09:00:00','2026-07-20 14:59:08'),
(1769,'COA-2016-169','Wireless Router',2,1,'2016-07-13',58180.26,1,NULL,NULL,'Office of the Mayor - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-15 09:00:00','2026-07-20 14:59:08'),
(1770,'COA-2024-164','Hand Tractor',9,5,'2024-05-21',109792.14,2,'Pedro Bautista',5,'Office of the Vice Mayor - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-24 09:00:00','2026-07-17 18:12:48'),
(1771,'COA-2019-163','Air Conditioning Unit (1.5HP Split Type)',1,1,'2019-07-31',6421.07,7,'Josefa Navarro',1,'Treasury Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2019-08-01 09:00:00','2026-07-20 14:59:08'),
(1772,'COA-2025-164','Weighing Scale (Digital)',8,1,'2025-08-03',95199.81,4,'Romeo Garcia',NULL,'Human Resource Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-06 09:00:00','2026-07-20 14:59:08'),
(1773,'COA-2017-192','Weighing Scale (Digital)',8,1,'2017-10-23',35785.39,1,'Alfredo Gonzales',1,'Office of the Mayor - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-26 09:00:00','2026-07-20 14:59:08'),
(1774,'COA-2020-132','Inflatable Rescue Boat',10,1,'2020-11-21',80969.38,7,'Manuel Villanueva',1,'Treasury Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-22 09:00:00','2026-07-17 18:12:48'),
(1775,'COA-2023-191','Ambulance Unit',5,1,'2023-05-17',663699.91,4,'Luz Mendoza',1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-19 09:00:00','2026-07-17 18:12:48'),
(1776,'COA-2020-133','Grass Cutter (Riding Type)',6,1,'2020-08-10',2240859.42,2,NULL,1,'Office of the Vice Mayor - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-10 09:00:00','2026-07-17 18:12:48'),
(1777,'COA-2026-089','Weighing Scale (Digital)',8,1,'2026-01-07',1738.97,10,'Luz Salazar',1,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-09 09:00:00','2026-07-17 18:12:48'),
(1778,'COA-2020-134','Grass Cutter (Riding Type)',6,1,'2020-05-18',1154630.63,14,'Corazon Flores',NULL,'Municipal Agriculture Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-05-21 09:00:00','2026-07-17 18:12:48'),
(1779,'COA-2021-165','Bulldozer',6,1,'2021-01-23',3026378.27,14,NULL,NULL,'Municipal Agriculture Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-25 09:00:00','2026-07-20 14:59:08'),
(1780,'COA-2017-193','LCD/LED Monitor 24\"',2,1,'2017-10-01',38528.17,15,'Carmen Domingo',1,'General Services Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-10-04 09:00:00','2026-07-17 18:12:48'),
(1781,'COA-2019-164','Microwave Oven',1,1,'2019-04-19',8339.66,3,'Alfredo Domingo',1,'Sangguniang Bayan Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-19 09:00:00','2026-07-20 14:59:08'),
(1782,'COA-2025-165','Digital Blood Pressure Monitor',8,1,'2025-10-31',1906.50,4,'Alfredo Aguilar',NULL,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-02 09:00:00','2026-07-17 18:12:48'),
(1783,'COA-2016-170','Sprayer (Backpack, Motorized)',9,2,'2016-02-01',33240.34,5,'Ana Bautista',2,'Budget Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-01 09:00:00','2026-07-20 14:59:08'),
(1784,'COA-2016-171','Conference Table (8-Seater)',3,2,'2016-02-23',9956.69,10,'Carlos Aquino',NULL,'Municipal Engineering Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-24 09:00:00','2026-07-20 14:59:08'),
(1785,'COA-2018-176','Nebulizer Machine',8,1,'2018-07-23',106953.96,4,'Ana Flores',1,'Human Resource Management Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-25 09:00:00','2026-07-17 18:12:48'),
(1786,'COA-2017-194','Oxygen Tank with Regulator',8,1,'2017-11-05',110938.99,5,'Gloria Aguilar',1,'Budget Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2017-11-07 09:00:00','2026-07-20 12:47:01'),
(1787,'COA-2016-172','Rice Thresher',9,5,'2016-04-29',6534.67,8,'Romeo Villanueva',5,'Assessor\'s Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-05-01 09:00:00','2026-07-20 14:59:08'),
(1788,'COA-2024-165','Steel Filing Cabinet (4-Drawer)',3,1,'2024-07-13',8916.02,17,'Divina Pascual',1,'Disaster Risk Reduction and Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-14 09:00:00','2026-07-17 18:12:48'),
(1789,'COA-2016-173','Inflatable Rescue Boat',10,1,'2016-04-02',22647.21,8,'Gloria Gonzales',1,'Assessor\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2016-04-04 09:00:00','2026-07-17 18:12:48'),
(1790,'COA-2025-166','Dump Truck',5,1,'2025-03-20',1154370.55,8,'Antonio Castillo',1,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-03-21 09:00:00','2026-07-17 18:12:48'),
(1791,'COA-2018-177','Electric Fan (Stand Type)',1,1,'2018-02-03',46291.07,9,'Teresa Navarro',1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2018-02-04 09:00:00','2026-07-17 18:12:48'),
(1792,'COA-2019-165','Vacuum Cleaner',1,1,'2019-09-20',26634.13,13,'Ernesto Ramos',1,'Municipal Social Welfare and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-22 09:00:00','2026-07-17 18:12:48'),
(1793,'COA-2019-166','CCTV Camera (Outdoor)',7,1,'2019-05-09',40704.03,3,'Carmen Flores',1,'Sangguniang Bayan Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-11 09:00:00','2026-07-17 18:12:48'),
(1794,'COA-2019-167','IP Desk Phone',7,1,'2019-01-08',22042.86,10,'Leonora Mendoza',1,'Municipal Engineering Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-08 09:00:00','2026-07-20 14:59:08'),
(1795,'COA-2018-178','Multi-Purpose Van',5,1,'2018-05-20',1346496.60,6,'Ramon Santos',NULL,'Accounting Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-23 09:00:00','2026-07-17 18:12:48'),
(1796,'COA-2021-166','24-Port Network Switch',2,1,'2021-12-29',31595.37,11,'Eduardo Dela Cruz',1,'Municipal Planning and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-31 09:00:00','2026-07-20 14:59:08'),
(1797,'COA-2018-179','Stretcher (Foldable)',8,1,'2018-09-06',27762.35,2,'Divina Castillo',1,'Office of the Vice Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-07 09:00:00','2026-07-17 18:12:48'),
(1798,'COA-2020-135','Visitor\'s Chair (Stackable)',3,1,'2020-05-03',8691.51,17,NULL,1,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2020-05-05 09:00:00','2026-07-20 14:59:08'),
(1799,'COA-2025-167','Swivel Office Chair',3,1,'2025-04-19',9294.55,5,'Cecilia Mendoza',1,'Budget Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-04-21 09:00:00','2026-07-20 12:47:01'),
(1800,'COA-2018-180','Water Dispenser (Hot & Cold)',1,1,'2018-06-25',45518.85,13,'Carlos Bautista',NULL,'Municipal Social Welfare and Development Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-06-26 09:00:00','2026-07-17 18:12:48'),
(1801,'COA-2017-195','Electric Fan (Stand Type)',1,1,'2017-01-25',8077.75,14,'Elena Torres',1,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-26 09:00:00','2026-07-17 18:12:48'),
(1802,'COA-2020-136','Steel Filing Cabinet (4-Drawer)',3,2,'2020-10-28',5118.83,11,'Manuel Marquez',2,'Municipal Planning and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2020-10-31 09:00:00','2026-07-17 18:12:48'),
(1803,'COA-2018-181','Fire Extinguisher (10lbs)',10,1,'2018-07-18',28565.88,5,'Norma Torres',1,'Budget Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-07-20 09:00:00','2026-07-20 12:47:01'),
(1804,'COA-2019-168','LCD/LED Monitor 24\"',2,1,'2019-09-19',29590.77,10,'Alfredo Flores',NULL,'Municipal Engineering Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-09-19 09:00:00','2026-07-17 18:12:48'),
(1805,'COA-2023-192','Grass Cutter (Riding Type)',6,1,'2023-08-07',2343003.89,7,'Jose Del Rosario',1,'Treasury Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-08 09:00:00','2026-07-17 18:12:48'),
(1806,'COA-2016-174','Oxygen Tank with Regulator',8,1,'2016-10-01',4640.57,14,'Cecilia Santos',1,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-01 09:00:00','2026-07-17 18:12:48'),
(1807,'COA-2023-193','Paper Shredder (Heavy Duty)',4,1,'2023-07-28',27229.08,3,'Imelda Pascual',1,'Sangguniang Bayan Office - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-28 09:00:00','2026-07-20 14:59:08'),
(1808,'COA-2022-166','Nebulizer Machine',8,1,'2022-01-17',70914.19,4,'Pedro Domingo',1,'Human Resource Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2022-01-17 09:00:00','2026-07-17 18:12:48'),
(1809,'COA-2018-182','Fire Extinguisher (10lbs)',10,1,'2018-02-27',5723.94,10,NULL,NULL,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-27 09:00:00','2026-07-20 14:59:08'),
(1810,'COA-2017-196','Wireless Router',2,1,'2017-08-09',41113.59,7,'Rodrigo Rivera',1,'Treasury Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-12 09:00:00','2026-07-20 14:59:08'),
(1811,'COA-2024-166','Thermal Scanner',8,1,'2024-12-26',50409.04,7,'Romeo Castillo',1,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2024-12-28 09:00:00','2026-07-20 14:59:08'),
(1812,'COA-2023-194','Water Tanker Truck',6,1,'2023-11-08',1469820.12,6,'Francisco Flores',1,'Accounting Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-11-11 09:00:00','2026-07-17 18:12:48'),
(1813,'COA-2025-168','Road Roller',6,1,'2025-01-21',1743675.50,8,'Imelda Domingo',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-22 09:00:00','2026-07-17 18:12:48'),
(1814,'COA-2017-197','Rescue Rope Kit',10,1,'2017-10-16',27917.43,14,'Luz Marquez',1,'Municipal Agriculture Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-16 09:00:00','2026-07-17 18:12:48'),
(1815,'COA-2019-169','Steel Locker Cabinet',3,5,'2019-09-01',26092.09,14,NULL,5,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-01 09:00:00','2026-07-17 18:12:48'),
(1816,'COA-2022-167','Stretcher (Foldable)',8,1,'2022-09-12',89153.87,6,'Corazon Pascual',1,'Accounting Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-12 09:00:00','2026-07-20 14:59:08'),
(1817,'COA-2025-169','Patrol Motorcycle',5,1,'2025-09-28',1599300.55,14,NULL,1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-30 09:00:00','2026-07-20 14:59:08'),
(1818,'COA-2026-090','Electric Kettle',1,1,'2026-03-19',53554.45,10,'Francisco Garcia',1,'Municipal Engineering Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-22 09:00:00','2026-07-20 14:59:08'),
(1819,'COA-2017-198','Water Pump (Irrigation)',9,2,'2017-01-18',101545.85,5,'Pedro Flores',2,'Budget Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-19 09:00:00','2026-07-20 12:47:01'),
(1820,'COA-2020-137','Megaphone (Bullhorn)',7,1,'2020-06-27',33518.36,16,'Carlos Aguilar',1,'Information and Communications Technology Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2020-06-28 09:00:00','2026-07-20 14:59:08'),
(1821,'COA-2016-175','Executive Office Desk',3,5,'2016-04-20',9030.37,5,NULL,5,'Budget Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-04-23 09:00:00','2026-07-20 14:59:08'),
(1822,'COA-2023-195','CCTV Camera (Outdoor)',7,1,'2023-07-30',18693.59,15,NULL,NULL,'General Services Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-30 09:00:00','2026-07-20 14:59:08'),
(1823,'COA-2016-176','Laminating Machine',4,1,'2016-02-05',42687.13,13,'Gloria Villanueva',NULL,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-05 09:00:00','2026-07-20 14:59:08'),
(1824,'COA-2025-170','Air Conditioning Unit (1.5HP Split Type)',1,1,'2025-09-21',10142.50,4,'Ernesto Santos',1,'Human Resource Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-21 09:00:00','2026-07-20 14:59:08'),
(1825,'COA-2017-199','Ambulance Unit',5,1,'2017-03-25',1053716.08,13,NULL,1,'Municipal Social Welfare and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-27 09:00:00','2026-07-20 14:59:08'),
(1826,'COA-2018-183','Refrigerator (2-Door)',1,1,'2018-11-11',5715.68,10,'Elena Santos',NULL,'Municipal Engineering Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-11 09:00:00','2026-07-20 14:59:08'),
(1827,'COA-2021-167','All-in-One Inkjet Printer',2,1,'2021-10-10',44230.32,9,'Carmen Rivera',1,'Civil Registrar\'s Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-10-12 09:00:00','2026-07-20 14:59:08'),
(1828,'COA-2017-200','Ambulance Unit',5,1,'2017-03-26',1921391.14,15,'Ramon Reyes',NULL,'General Services Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-28 09:00:00','2026-07-17 18:12:48'),
(1829,'COA-2023-196','Chainsaw (Rescue Type)',10,1,'2023-10-13',62062.94,17,'Danilo Bautista',NULL,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-16 09:00:00','2026-07-20 14:59:08'),
(1830,'COA-2022-168','Document Scanner',2,1,'2022-05-18',43661.78,3,'Francisco Aquino',1,'Sangguniang Bayan Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-18 09:00:00','2026-07-17 18:12:48'),
(1831,'COA-2019-170','Grass Cutter (Riding Type)',6,1,'2019-09-25',941031.19,1,'Carmen Fernandez',NULL,'Office of the Mayor - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-09-28 09:00:00','2026-07-17 18:12:48'),
(1832,'COA-2018-184','Water Pump (Irrigation)',9,1,'2018-10-08',177774.14,12,'Eduardo Rivera',NULL,'Municipal Health Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-10-10 09:00:00','2026-07-17 18:12:48'),
(1833,'COA-2016-177','Generator Set (25 kVA)',6,1,'2016-09-29',1291215.00,2,'Gloria Aguilar',NULL,'Office of the Vice Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2016-09-29 09:00:00','2026-07-17 18:12:48'),
(1834,'COA-2026-091','Bulletin Board (Cork, Framed)',4,1,'2026-02-07',14083.71,6,'Teresa Navarro',NULL,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-07 09:00:00','2026-07-17 18:12:48'),
(1835,'COA-2017-201','Bookshelf (Wooden, 5-Tier)',3,1,'2017-05-30',12629.37,11,NULL,1,'Municipal Planning and Development Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-01 09:00:00','2026-07-17 18:12:48'),
(1836,'COA-2025-171','Digital Blood Pressure Monitor',8,1,'2025-12-08',77210.67,5,'Elena Gonzales',NULL,'Budget Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-12-11 09:00:00','2026-07-20 14:59:08'),
(1837,'COA-2017-202','Water Pump (Irrigation)',9,1,'2017-07-28',125866.40,10,'Ricardo Domingo',NULL,'Municipal Engineering Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2017-07-30 09:00:00','2026-07-17 18:12:48'),
(1838,'COA-2016-178','Swivel Office Chair',3,1,'2016-07-15',4973.77,3,'Luz Salazar',NULL,'Sangguniang Bayan Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-16 09:00:00','2026-07-20 14:59:08'),
(1839,'COA-2017-203','Autoclave Sterilizer',8,1,'2017-01-19',112259.06,16,'Eduardo Fernandez',1,'Information and Communications Technology Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-21 09:00:00','2026-07-20 14:59:08'),
(1840,'COA-2016-179','CCTV Camera (Outdoor)',7,1,'2016-06-15',28399.50,10,'Ricardo Flores',1,'Municipal Engineering Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-17 09:00:00','2026-07-20 14:59:08'),
(1841,'COA-2023-197','Ambulance Unit',5,1,'2023-07-25',1643763.85,5,'Ernesto Pascual',1,'Budget Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-27 09:00:00','2026-07-20 14:59:08'),
(1842,'COA-2021-168','Fire Extinguisher (10lbs)',10,1,'2021-02-21',35651.66,1,'Imelda Flores',1,'Office of the Mayor - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-02-23 09:00:00','2026-07-17 18:12:48'),
(1843,'COA-2026-092','24-Port Network Switch',2,1,'2026-03-07',9897.07,3,'Maria Santos',1,'Sangguniang Bayan Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-08 09:00:00','2026-07-20 14:59:08'),
(1844,'COA-2023-198','Life Vest',10,1,'2023-07-04',80556.68,7,NULL,1,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-04 09:00:00','2026-07-20 14:59:08'),
(1845,'COA-2021-169','Paper Shredder (Heavy Duty)',4,1,'2021-07-08',40207.63,12,'Eduardo Domingo',NULL,'Municipal Health Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-08 09:00:00','2026-07-20 14:59:08'),
(1846,'COA-2023-199','Megaphone (Bullhorn)',7,1,'2023-08-12',12702.77,10,'Romeo Torres',1,'Municipal Engineering Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-14 09:00:00','2026-07-20 14:59:08'),
(1847,'COA-2019-171','Sprayer (Backpack, Motorized)',9,5,'2019-06-25',62287.31,5,NULL,5,'Budget Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-26 09:00:00','2026-07-20 14:59:08'),
(1848,'COA-2022-169','Steel Locker Cabinet',3,1,'2022-02-14',3514.47,1,'Manuel Dela Cruz',1,'Office of the Mayor - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-02-14 09:00:00','2026-07-17 18:12:48'),
(1849,'COA-2025-172','Steel Filing Cabinet (4-Drawer)',3,2,'2025-11-02',26776.81,16,'Maria Fernandez',2,'Information and Communications Technology Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-11-04 09:00:00','2026-07-17 18:12:48'),
(1850,'COA-2017-204','Photocopier Machine (Multi-function)',4,1,'2017-01-01',6525.59,1,'Maria Rivera',1,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-01 09:00:00','2026-07-17 18:12:48'),
(1851,'COA-2017-205','Seedling Tray Set',9,1,'2017-12-11',62790.29,2,NULL,1,'Office of the Vice Mayor - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-12 09:00:00','2026-07-20 14:59:08'),
(1852,'COA-2018-185','Calculator (Desktop Printing)',4,1,'2018-12-11',42268.15,2,'Jose Flores',NULL,'Office of the Vice Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-12-14 09:00:00','2026-07-17 18:12:48'),
(1853,'COA-2021-170','Steel Filing Cabinet (4-Drawer)',3,1,'2021-10-30',24061.73,14,NULL,1,'Municipal Agriculture Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2021-11-01 09:00:00','2026-07-17 18:12:48'),
(1854,'COA-2025-173','Paper Shredder (Heavy Duty)',4,1,'2025-04-15',5252.82,3,'Cecilia Torres',1,'Sangguniang Bayan Office - Storage Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-04-17 09:00:00','2026-07-17 18:12:48'),
(1855,'COA-2019-172','Oxygen Tank with Regulator',8,1,'2019-04-03',12717.74,17,'Ana Ocampo',NULL,'Disaster Risk Reduction and Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-04-03 09:00:00','2026-07-17 18:12:48'),
(1856,'COA-2020-138','Water Cooler/Dispenser',1,1,'2020-07-19',24924.89,4,'Ana Rivera',NULL,'Human Resource Management Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-07-22 09:00:00','2026-07-20 14:59:08'),
(1857,'COA-2022-170','Laminating Machine',4,1,'2022-02-09',4523.64,14,'Manuel Fernandez',1,'Municipal Agriculture Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-02-12 09:00:00','2026-07-17 18:12:48'),
(1858,'COA-2022-171','Farm Tool Kit',9,1,'2022-05-23',82491.92,1,'Manuel Castillo',1,'Office of the Mayor - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-24 09:00:00','2026-07-20 14:59:08'),
(1859,'COA-2022-172','Stretcher (Foldable)',8,1,'2022-07-06',97298.18,10,'Ana Garcia',NULL,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-08 09:00:00','2026-07-17 18:12:48'),
(1860,'COA-2016-180','CCTV Camera (Outdoor)',7,1,'2016-04-12',38140.70,10,NULL,NULL,'Municipal Engineering Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-04-14 09:00:00','2026-07-17 18:12:48'),
(1861,'COA-2024-167','Ambulance Unit',5,1,'2024-09-02',641380.78,4,NULL,1,'Human Resource Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-09-02 09:00:00','2026-07-17 18:12:48'),
(1862,'COA-2019-173','Concrete Mixer',6,1,'2019-12-08',614515.79,13,'Jose Fernandez',NULL,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2019-12-10 09:00:00','2026-07-17 18:12:48'),
(1863,'COA-2022-173','Dump Truck',5,1,'2022-08-31',1567544.63,9,'Francisco Gonzales',1,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-09-02 09:00:00','2026-07-20 14:59:08'),
(1864,'COA-2017-206','Paper Shredder (Heavy Duty)',4,1,'2017-05-20',48327.36,1,'Rodrigo Dela Cruz',1,'Office of the Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-05-20 09:00:00','2026-07-17 18:12:48'),
(1865,'COA-2023-200','Electric Kettle',1,1,'2023-06-02',10334.83,13,'Elena Torres',NULL,'Municipal Social Welfare and Development Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2023-06-04 09:00:00','2026-07-20 14:59:08'),
(1866,'COA-2017-207','Binding Machine',4,1,'2017-07-11',51700.77,1,NULL,1,'Office of the Mayor - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-07-11 09:00:00','2026-07-17 18:12:48'),
(1867,'COA-2023-201','Patrol Motorcycle',5,1,'2023-10-27',1021605.23,1,NULL,NULL,'Office of the Mayor - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-27 09:00:00','2026-07-20 14:59:08'),
(1868,'COA-2018-186','Handheld Two-Way Radio',7,1,'2018-11-13',33115.35,16,'Josefa Torres',NULL,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-11-14 09:00:00','2026-07-17 18:12:48'),
(1869,'COA-2019-174','Megaphone (Bullhorn)',7,1,'2019-12-20',24349.82,14,'Leonora Ramos',NULL,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-23 09:00:00','2026-07-17 18:12:48'),
(1870,'COA-2023-202','Rice Thresher',9,2,'2023-01-24',150370.06,14,'Manuel Villanueva',2,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-01-26 09:00:00','2026-07-20 14:59:08'),
(1871,'COA-2026-093','Microwave Oven',1,1,'2026-02-07',15294.42,17,'Rodrigo Aguilar',NULL,'Disaster Risk Reduction and Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-10 09:00:00','2026-07-17 18:12:48'),
(1872,'COA-2025-174','Chainsaw (Rescue Type)',10,1,'2025-09-19',4945.66,11,'Norma Villanueva',1,'Municipal Planning and Development Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-22 09:00:00','2026-07-17 18:12:48'),
(1873,'COA-2016-181','Partition Divider Panel',3,1,'2016-07-28',8713.76,1,NULL,NULL,'Office of the Mayor - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-07-28 09:00:00','2026-07-17 18:12:48'),
(1874,'COA-2019-175','Bookshelf (Wooden, 5-Tier)',3,1,'2019-01-09',7677.27,11,NULL,1,'Municipal Planning and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-12 09:00:00','2026-07-20 14:59:08'),
(1875,'COA-2019-176','Electric Fan (Stand Type)',1,1,'2019-11-07',37041.52,10,NULL,NULL,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-10 09:00:00','2026-07-20 14:59:08'),
(1876,'COA-2024-168','Bulletin Board (Cork, Framed)',4,1,'2024-06-01',41467.31,8,'Antonio Torres',1,'Assessor\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-01 09:00:00','2026-07-20 14:59:08'),
(1877,'COA-2020-139','Multi-Purpose Van',5,1,'2020-06-30',773138.51,6,'Ramon Garcia',1,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2020-07-03 09:00:00','2026-07-20 14:59:08'),
(1878,'COA-2021-171','Stretcher (Foldable)',8,1,'2021-12-04',67149.85,8,'Carmen Villanueva',NULL,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-04 09:00:00','2026-07-17 18:12:48'),
(1879,'COA-2019-177','Laptop Computer (Business Series)',2,1,'2019-08-20',13114.61,8,'Gloria Villanueva',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-23 09:00:00','2026-07-17 18:12:48'),
(1880,'COA-2021-172','Base Radio Station',7,1,'2021-04-25',25612.19,5,'Francisco Torres',1,'Budget Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-27 09:00:00','2026-07-20 14:59:08'),
(1881,'COA-2020-140','Oxygen Tank with Regulator',8,1,'2020-09-29',91684.49,12,'Ana Mendoza',NULL,'Municipal Health Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2020-09-29 09:00:00','2026-07-17 18:12:48'),
(1882,'COA-2017-208','Digital Blood Pressure Monitor',8,1,'2017-10-16',71314.92,13,NULL,1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-17 09:00:00','2026-07-20 14:59:08'),
(1883,'COA-2016-182','Inflatable Rescue Boat',10,1,'2016-10-29',71260.04,11,NULL,1,'Municipal Planning and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-31 09:00:00','2026-07-17 18:12:48'),
(1884,'COA-2020-141','Visitor\'s Chair (Stackable)',3,1,'2020-12-10',26596.83,14,NULL,1,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2020-12-10 09:00:00','2026-07-17 18:12:48'),
(1885,'COA-2023-203','Laser Printer (Monochrome)',2,1,'2023-04-17',11460.38,10,'Alfredo Flores',NULL,'Municipal Engineering Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-18 09:00:00','2026-07-17 18:12:48'),
(1886,'COA-2017-209','Bulletin Board (Cork, Framed)',4,1,'2017-06-26',25432.34,9,'Manuel Pascual',1,'Civil Registrar\'s Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-06-28 09:00:00','2026-07-17 18:12:48'),
(1887,'COA-2026-094','Service Vehicle (Sedan)',5,1,'2026-01-15',1362340.25,7,'Rodrigo Villanueva',NULL,'Treasury Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-01-16 09:00:00','2026-07-17 18:12:48'),
(1888,'COA-2021-173','Steel Filing Cabinet (4-Drawer)',3,1,'2021-06-04',9794.58,16,'Imelda Navarro',NULL,'Information and Communications Technology Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-06-07 09:00:00','2026-07-20 14:59:08'),
(1889,'COA-2018-187','Laser Printer (Monochrome)',2,1,'2018-05-25',46720.22,15,'Pedro Del Rosario',1,'General Services Office - Supply Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-05-27 09:00:00','2026-07-17 18:12:48'),
(1890,'COA-2017-210','Fire Extinguisher (10lbs)',10,1,'2017-10-03',57214.47,5,'Eduardo Santos',NULL,'Budget Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-05 09:00:00','2026-07-20 12:47:01'),
(1891,'COA-2023-204','Inflatable Rescue Boat',10,1,'2023-08-27',47321.12,17,'Luz Aquino',1,'Disaster Risk Reduction and Management Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-29 09:00:00','2026-07-20 14:59:08'),
(1892,'COA-2025-175','Water Dispenser (Hot & Cold)',1,1,'2025-01-26',2808.62,1,'Manuel Ocampo',NULL,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-01-27 09:00:00','2026-07-17 18:12:48'),
(1893,'COA-2017-211','Grass Cutter (Riding Type)',6,1,'2017-11-27',1251193.84,2,'Ernesto Domingo',NULL,'Office of the Vice Mayor - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-11-30 09:00:00','2026-07-20 14:59:08'),
(1894,'COA-2023-205','IP Desk Phone',7,1,'2023-08-14',15147.89,15,'Danilo Ocampo',NULL,'General Services Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-08-17 09:00:00','2026-07-17 18:12:48'),
(1895,'COA-2016-183','Digital Blood Pressure Monitor',8,1,'2016-10-20',104754.68,6,'Elena Flores',1,'Accounting Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-20 09:00:00','2026-07-17 18:12:48'),
(1896,'COA-2020-142','Rice Thresher',9,1,'2020-01-21',9064.39,6,'Carlos Del Rosario',1,'Accounting Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-01-24 09:00:00','2026-07-17 18:12:48'),
(1897,'COA-2022-174','Refrigerator (2-Door)',1,1,'2022-01-10',36546.92,8,'Elena Ocampo',1,'Assessor\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-01-11 09:00:00','2026-07-17 18:12:48'),
(1898,'COA-2016-184','Executive Office Desk',3,1,'2016-06-24',4667.96,2,'Danilo Bautista',1,'Office of the Vice Mayor - Main Office - Ground Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-06-25 09:00:00','2026-07-20 14:59:08'),
(1899,'COA-2017-212','Water Dispenser (Hot & Cold)',1,1,'2017-03-02',13876.31,11,'Carmen Santos',1,'Municipal Planning and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-05 09:00:00','2026-07-20 14:59:08'),
(1900,'COA-2022-175','Water Tanker Truck',6,1,'2022-10-16',754039.07,14,'Antonio Domingo',1,'Municipal Agriculture Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-16 09:00:00','2026-07-17 18:12:48'),
(1901,'COA-2021-174','LCD/LED Monitor 24\"',2,1,'2021-08-11',65506.52,17,'Elena Navarro',NULL,'Disaster Risk Reduction and Management Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-08-13 09:00:00','2026-07-17 18:12:48'),
(1902,'COA-2020-143','Laminating Machine',4,1,'2020-03-04',33653.97,1,'Carlos Gonzales',1,'Office of the Mayor - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-07 09:00:00','2026-07-20 14:59:08'),
(1903,'COA-2016-185','Multi-Purpose Van',5,1,'2016-10-08',969958.90,13,'Manuel Mendoza',1,'Municipal Social Welfare and Development Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-10-10 09:00:00','2026-07-20 14:59:08'),
(1904,'COA-2023-206','IP Desk Phone',7,1,'2023-09-03',9899.92,4,'Carmen Mendoza',1,'Human Resource Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-09-03 09:00:00','2026-07-17 18:12:48'),
(1905,'COA-2021-175','Handheld Two-Way Radio',7,1,'2021-05-16',38273.05,9,'Manuel Gonzales',1,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-19 09:00:00','2026-07-17 18:12:48'),
(1906,'COA-2016-186','Binding Machine',4,1,'2016-04-25',36559.59,1,'Corazon Fernandez',1,'Office of the Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-04-25 09:00:00','2026-07-20 14:59:08'),
(1907,'COA-2023-207','Swivel Office Chair',3,2,'2023-06-01',26259.13,4,'Corazon Flores',NULL,'Human Resource Management Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-06-02 09:00:00','2026-07-20 14:59:08'),
(1908,'COA-2016-187','Partition Divider Panel',3,1,'2016-12-01',4637.97,4,'Josefa Bautista',NULL,'Human Resource Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-04 09:00:00','2026-07-20 14:59:08'),
(1909,'COA-2019-178','Water Cooler/Dispenser',1,1,'2019-10-02',30105.56,16,'Alfredo Ocampo',1,'Information and Communications Technology Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-05 09:00:00','2026-07-20 14:59:08'),
(1910,'COA-2017-213','Water Dispenser (Hot & Cold)',1,1,'2017-10-22',8088.92,11,'Ramon Gonzales',1,'Municipal Planning and Development Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-10-22 09:00:00','2026-07-20 14:59:08'),
(1911,'COA-2020-144','Laptop Computer (Business Series)',2,1,'2020-11-07',45416.25,1,'Imelda Marquez',1,'Office of the Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-11-07 09:00:00','2026-07-20 14:59:08'),
(1912,'COA-2021-176','Concrete Mixer',6,1,'2021-01-11',857324.15,12,NULL,NULL,'Municipal Health Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-11 09:00:00','2026-07-20 14:59:08'),
(1913,'COA-2021-177','Document Scanner',2,1,'2021-11-22',57565.08,7,NULL,1,'Treasury Office - Main Office - Ground Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2021-11-23 09:00:00','2026-07-20 14:59:08'),
(1914,'COA-2019-179','Base Radio Station',7,1,'2019-11-26',36302.15,16,'Ana Domingo',NULL,'Information and Communications Technology Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2019-11-27 09:00:00','2026-07-17 18:12:48'),
(1915,'COA-2024-169','Patrol Motorcycle',5,1,'2024-06-16',529465.73,2,'Alfredo Reyes',1,'Office of the Vice Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-06-18 09:00:00','2026-07-17 18:12:48'),
(1916,'COA-2023-208','Fax Machine',4,1,'2023-10-17',59035.93,11,'Elena Del Rosario',1,'Municipal Planning and Development Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-17 09:00:00','2026-07-20 14:59:08'),
(1917,'COA-2017-214','Laminating Machine',4,1,'2017-08-18',51186.13,5,NULL,1,'Budget Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-08-19 09:00:00','2026-07-20 14:59:08'),
(1918,'COA-2025-176','External Hard Drive 2TB',2,1,'2025-05-01',74676.41,9,NULL,1,'Civil Registrar\'s Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-01 09:00:00','2026-07-20 14:59:08'),
(1919,'COA-2022-176','CCTV Camera (Outdoor)',7,1,'2022-05-29',13597.61,8,'Alfredo Torres',1,'Assessor\'s Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-05-31 09:00:00','2026-07-17 18:12:48'),
(1920,'COA-2021-178','Nebulizer Machine',8,1,'2021-11-05',93357.65,13,'Rodrigo Navarro',1,'Municipal Social Welfare and Development Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-11-07 09:00:00','2026-07-20 14:59:08'),
(1921,'COA-2023-209','Refrigerator (2-Door)',1,1,'2023-11-17',26697.37,6,'Romeo Torres',1,'Accounting Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-11-20 09:00:00','2026-07-20 14:59:08'),
(1922,'COA-2018-188','Fax Machine',4,1,'2018-02-25',31074.92,16,'Pedro Bautista',1,'Information and Communications Technology Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-02-25 09:00:00','2026-07-20 14:59:08'),
(1923,'COA-2024-170','Conference Table (8-Seater)',3,1,'2024-03-29',19647.66,6,'Divina Ocampo',NULL,'Accounting Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-31 09:00:00','2026-07-17 18:12:48'),
(1924,'COA-2017-215','Motorcycle (Service Unit)',5,1,'2017-01-20',624786.57,1,'Luz Ramos',1,'Office of the Mayor - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-01-23 09:00:00','2026-07-20 14:59:08'),
(1925,'COA-2023-210','Microwave Oven',1,1,'2023-10-10',15344.16,6,'Carmen Dela Cruz',1,'Accounting Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-10-11 09:00:00','2026-07-17 18:12:48'),
(1926,'COA-2019-180','PABX Telephone System',7,1,'2019-10-09',44561.97,3,'Divina Navarro',1,'Sangguniang Bayan Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2019-10-11 09:00:00','2026-07-20 14:59:08'),
(1927,'COA-2019-181','Wheelchair',8,1,'2019-08-03',99951.94,2,'Alfredo Castillo',1,'Office of the Vice Mayor - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'For monitoring.',0,NULL,NULL,NULL,'2019-08-05 09:00:00','2026-07-17 18:12:48'),
(1928,'COA-2019-182','Vacuum Cleaner',1,1,'2019-07-27',19275.06,7,'Norma Navarro',1,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-07-28 09:00:00','2026-07-20 14:59:08'),
(1929,'COA-2022-177','Rescue Rope Kit',10,1,'2022-09-23',74109.20,14,'Elena Flores',1,'Municipal Agriculture Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2022-09-25 09:00:00','2026-07-20 14:59:08'),
(1930,'COA-2019-183','Dump Truck',5,1,'2019-02-22',1554120.68,5,'Juan Domingo',1,'Budget Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-02-25 09:00:00','2026-07-20 12:47:01'),
(1931,'COA-2018-189','Water Pump (Irrigation)',9,1,'2018-09-02',86920.93,8,'Norma Rivera',NULL,'Assessor\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-03 09:00:00','2026-07-17 18:12:48'),
(1932,'COA-2019-184','Service Pick-up Truck',5,1,'2019-03-10',1723052.19,6,'Corazon Garcia',NULL,'Accounting Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-03-11 09:00:00','2026-07-17 18:12:48'),
(1933,'COA-2024-171','Concrete Mixer',6,1,'2024-07-06',1944410.79,6,NULL,NULL,'Accounting Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-09 09:00:00','2026-07-20 14:59:08'),
(1934,'COA-2022-178','Vacuum Cleaner',1,1,'2022-05-20',44850.10,8,'Teresa Villanueva',1,'Assessor\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Reassigned from previous office.',0,NULL,NULL,NULL,'2022-05-22 09:00:00','2026-07-20 14:59:08'),
(1935,'COA-2018-190','Desktop Computer Set (Core i5)',2,1,'2018-04-04',9935.58,17,'Eduardo Castillo',NULL,'Disaster Risk Reduction and Management Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-04-06 09:00:00','2026-07-17 18:12:48'),
(1936,'COA-2023-211','Inflatable Rescue Boat',10,1,'2023-06-24',50020.07,13,'Francisco Navarro',1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-24 09:00:00','2026-07-20 14:59:08'),
(1937,'COA-2022-179','Electric Fan (Stand Type)',1,1,'2022-07-21',6962.69,14,'Francisco Santos',1,'Municipal Agriculture Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2022-07-22 09:00:00','2026-07-17 18:12:48'),
(1938,'COA-2019-185','Autoclave Sterilizer',8,1,'2019-10-11',58431.48,4,'Teresa Ocampo',1,'Human Resource Management Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-10-14 09:00:00','2026-07-17 18:12:48'),
(1939,'COA-2020-145','Water Cooler/Dispenser',1,1,'2020-04-23',37264.78,4,'Romeo Ocampo',NULL,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-04-26 09:00:00','2026-07-20 14:59:08'),
(1940,'COA-2019-186','Fire Extinguisher (10lbs)',10,1,'2019-09-04',84113.74,17,NULL,1,'Disaster Risk Reduction and Management Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-04 09:00:00','2026-07-20 14:59:08'),
(1941,'COA-2019-187','Binding Machine',4,1,'2019-11-06',5824.79,16,'Norma Ramos',1,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-06 09:00:00','2026-07-17 18:12:48'),
(1942,'COA-2019-188','Digital Blood Pressure Monitor',8,1,'2019-05-16',101571.41,4,'Leonora Del Rosario',1,'Human Resource Management Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-16 09:00:00','2026-07-17 18:12:48'),
(1943,'COA-2024-172','Service Vehicle (Sedan)',5,1,'2024-11-08',1551073.77,17,'Elena Rivera',1,'Disaster Risk Reduction and Management Office - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-11-08 09:00:00','2026-07-20 14:59:08'),
(1944,'COA-2019-189','Road Roller',6,1,'2019-12-07',403994.20,17,'Juan Santos',NULL,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-12-07 09:00:00','2026-07-17 18:12:48'),
(1945,'COA-2023-212','Electric Kettle',1,1,'2023-03-17',10240.06,10,NULL,1,'Municipal Engineering Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-18 09:00:00','2026-07-17 18:12:48'),
(1946,'COA-2024-173','Vacuum Cleaner',1,1,'2024-05-19',13820.68,7,'Luz Torres',NULL,'Treasury Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-20 09:00:00','2026-07-17 18:12:48'),
(1947,'COA-2023-213','Rice Thresher',9,1,'2023-07-24',42744.83,3,'Teresa Santos',NULL,'Sangguniang Bayan Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-07-27 09:00:00','2026-07-20 14:59:08'),
(1948,'COA-2025-177','Multi-Purpose Van',5,1,'2025-09-18',1256722.15,9,NULL,1,'Civil Registrar\'s Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-20 09:00:00','2026-07-20 14:59:08'),
(1949,'COA-2022-180','Water Cooler/Dispenser',1,1,'2022-11-20',45220.16,17,'Josefa Aquino',1,'Disaster Risk Reduction and Management Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-21 09:00:00','2026-07-17 18:12:48'),
(1950,'COA-2025-178','Rescue Rope Kit',10,1,'2025-07-07',43489.64,12,'Ramon Dela Cruz',1,'Municipal Health Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-08 09:00:00','2026-07-17 18:12:48'),
(1951,'COA-2021-179','Nebulizer Machine',8,1,'2021-03-28',11041.28,14,'Carmen Torres',1,'Municipal Agriculture Office - Reception Area','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2021-03-29 09:00:00','2026-07-17 18:12:48'),
(1952,'COA-2022-181','Photocopier Machine (Multi-function)',4,1,'2022-12-22',51903.51,2,'Maria Navarro',1,'Office of the Vice Mayor - Reception Area','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-12-22 09:00:00','2026-07-20 14:59:08'),
(1953,'COA-2019-190','Service Pick-up Truck',5,1,'2019-11-07',1369334.06,9,NULL,NULL,'Civil Registrar\'s Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-09 09:00:00','2026-07-17 18:12:48'),
(1954,'COA-2020-146','Executive Office Desk',3,1,'2020-10-26',24293.59,14,'Francisco Dela Cruz',1,'Municipal Agriculture Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-27 09:00:00','2026-07-17 18:12:48'),
(1955,'COA-2016-188','Backhoe Loader',6,1,'2016-11-14',2060020.06,14,'Ricardo Navarro',1,'Municipal Agriculture Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-11-15 09:00:00','2026-07-17 18:12:48'),
(1956,'COA-2024-174','Sprayer (Backpack, Motorized)',9,1,'2024-05-25',74416.47,7,'Norma Villanueva',1,'Treasury Office - Field Station','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-27 09:00:00','2026-07-20 14:59:08'),
(1957,'COA-2024-175','Water Cooler/Dispenser',1,1,'2024-01-30',40986.58,9,'Imelda Fernandez',NULL,'Civil Registrar\'s Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-01-30 09:00:00','2026-07-17 18:12:48'),
(1958,'COA-2016-189','Grass Cutter (Riding Type)',6,1,'2016-03-09',2179426.02,12,'Danilo Mendoza',1,'Municipal Health Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-12 09:00:00','2026-07-17 18:12:48'),
(1959,'COA-2019-191','Water Cooler/Dispenser',1,1,'2019-02-13',38221.48,11,'Teresa Mendoza',NULL,'Municipal Planning and Development Office - Records Section','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-02-13 09:00:00','2026-07-17 18:12:48'),
(1960,'COA-2020-147','Hand Tractor',9,1,'2020-03-20',89023.69,13,'Elena Torres',1,'Municipal Social Welfare and Development Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-23 09:00:00','2026-07-17 18:12:48'),
(1961,'COA-2025-179','Service Pick-up Truck',5,1,'2025-04-12',454659.82,10,'Ramon Villanueva',1,'Municipal Engineering Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2025-04-12 09:00:00','2026-07-20 14:59:08'),
(1962,'COA-2021-180','Calculator (Desktop Printing)',4,1,'2021-05-23',54974.77,17,NULL,1,'Disaster Risk Reduction and Management Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-05-24 09:00:00','2026-07-17 18:12:48'),
(1963,'COA-2019-192','Weighing Scale (Digital)',8,1,'2019-05-23',25648.76,16,NULL,1,'Information and Communications Technology Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-05-26 09:00:00','2026-07-17 18:12:48'),
(1964,'COA-2018-191','Water Tanker Truck',6,1,'2018-12-31',2551471.19,7,'Jose Aquino',1,'Treasury Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-03 09:00:00','2026-07-20 14:59:08'),
(1965,'COA-2019-193','Seedling Tray Set',9,5,'2019-11-08',13716.85,11,'Luz Marquez',5,'Municipal Planning and Development Office - Main Office - 2nd Floor','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-11 09:00:00','2026-07-20 14:59:08'),
(1966,'COA-2021-181','24-Port Network Switch',2,1,'2021-03-02',66116.07,13,'Cecilia Torres',1,'Municipal Social Welfare and Development Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-03-03 09:00:00','2026-07-17 18:12:48'),
(1967,'COA-2018-192','Refrigerator (2-Door)',1,1,'2018-03-14',45504.02,2,NULL,NULL,'Office of the Vice Mayor - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-15 09:00:00','2026-07-20 14:59:08'),
(1968,'COA-2022-182','Inflatable Rescue Boat',10,1,'2022-06-10',71244.34,12,'Ernesto Reyes',1,'Municipal Health Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-13 09:00:00','2026-07-20 14:59:08'),
(1969,'COA-2019-194','LCD/LED Monitor 24\"',2,1,'2019-04-26',13873.44,3,'Antonio Fernandez',1,'Sangguniang Bayan Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2019-04-26 09:00:00','2026-07-17 18:12:48'),
(1970,'COA-2021-182','Ambulance Unit',5,1,'2021-01-16',1382441.86,1,'Ana Reyes',1,'Office of the Mayor - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-01-16 09:00:00','2026-07-20 14:59:08'),
(1971,'COA-2024-176','Autoclave Sterilizer',8,1,'2024-04-24',29629.63,14,'Antonio Villanueva',1,'Municipal Agriculture Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-25 09:00:00','2026-07-20 14:59:08'),
(1972,'COA-2019-195','Rescue Rope Kit',10,1,'2019-10-29',7122.10,9,'Jose Cruz',NULL,'Civil Registrar\'s Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2019-10-30 09:00:00','2026-07-20 14:59:08'),
(1973,'COA-2016-190','Handheld Two-Way Radio',7,1,'2016-03-11',40544.79,3,NULL,1,'Sangguniang Bayan Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-03-12 09:00:00','2026-07-17 18:12:48'),
(1974,'COA-2017-216','Base Radio Station',7,1,'2017-05-30',31698.10,17,'Josefa Aquino',NULL,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2017-05-30 09:00:00','2026-07-20 14:59:08'),
(1975,'COA-2022-183','Patrol Motorcycle',5,1,'2022-06-04',2081697.75,16,'Juan Dela Cruz',NULL,'Information and Communications Technology Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-06-05 09:00:00','2026-07-17 18:12:48'),
(1976,'COA-2024-177','Oxygen Tank with Regulator',8,1,'2024-07-10',66825.28,5,'Danilo Torres',NULL,'Budget Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-07-11 09:00:00','2026-07-20 12:47:01'),
(1977,'COA-2024-178','Rescue Rope Kit',10,1,'2024-03-29',25630.24,16,'Francisco Bautista',NULL,'Information and Communications Technology Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-29 09:00:00','2026-07-17 18:12:48'),
(1978,'COA-2023-214','Rice Thresher',9,5,'2023-12-03',74000.04,1,'Maria Villanueva',5,'Office of the Mayor - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2023-12-05 09:00:00','2026-07-17 18:12:48'),
(1979,'COA-2025-180','IP Desk Phone',7,1,'2025-07-02',40172.38,12,'Divina Domingo',1,'Municipal Health Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-07-04 09:00:00','2026-07-17 18:12:48'),
(1980,'COA-2019-196','Inflatable Rescue Boat',10,1,'2019-09-15',38469.26,17,'Carlos Reyes',NULL,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-09-17 09:00:00','2026-07-20 14:59:08'),
(1981,'COA-2021-183','Seedling Tray Set',9,5,'2021-12-14',81653.76,16,NULL,5,'Information and Communications Technology Office - Conference Room','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-12-15 09:00:00','2026-07-20 14:59:08'),
(1982,'COA-2023-215','Water Dispenser (Hot & Cold)',1,1,'2023-04-04',48965.08,14,'Eduardo Dela Cruz',1,'Municipal Agriculture Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-04-06 09:00:00','2026-07-20 14:59:08'),
(1983,'COA-2023-216','Emergency Light Tower',10,1,'2023-06-18',43591.14,9,NULL,NULL,'Civil Registrar\'s Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-06-18 09:00:00','2026-07-20 14:59:08'),
(1984,'COA-2024-179','Rice Thresher',9,5,'2024-03-08',33238.21,11,'Luz Villanueva',NULL,'Municipal Planning and Development Office - Main Office - 2nd Floor','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-03-11 09:00:00','2026-07-20 14:59:08'),
(1985,'COA-2020-148','Typewriter (Manual)',4,1,'2020-12-09',37769.24,10,'Romeo Santos',NULL,'Municipal Engineering Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-12-09 09:00:00','2026-07-20 14:59:08'),
(1986,'COA-2016-191','Megaphone (Bullhorn)',7,1,'2016-02-02',26155.21,16,NULL,NULL,'Information and Communications Technology Office - Staff Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-02-05 09:00:00','2026-07-17 18:12:48'),
(1987,'COA-2020-149','Swivel Office Chair',3,1,'2020-02-14',15284.40,6,'Cecilia Dela Cruz',1,'Accounting Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-02-16 09:00:00','2026-07-17 18:12:48'),
(1988,'COA-2026-095','PABX Telephone System',7,1,'2026-03-02',29663.39,16,'Corazon Domingo',1,'Information and Communications Technology Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-03-04 09:00:00','2026-07-17 18:12:48'),
(1989,'COA-2019-197','Rescue Rope Kit',10,1,'2019-10-03',9379.50,16,'Carlos Santos',1,'Information and Communications Technology Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-10-06 09:00:00','2026-07-17 18:12:48'),
(1990,'COA-2019-198','Chainsaw (Rescue Type)',10,1,'2019-01-29',67893.99,16,NULL,1,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-29 09:00:00','2026-07-17 18:12:48'),
(1991,'COA-2020-150','Bookshelf (Wooden, 5-Tier)',3,1,'2020-12-22',23686.02,14,'Divina Cruz',1,'Municipal Agriculture Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-12-22 09:00:00','2026-07-17 18:12:48'),
(1992,'COA-2019-199','Backhoe Loader',6,1,'2019-06-26',2092425.42,14,'Corazon Aguilar',1,'Municipal Agriculture Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-28 09:00:00','2026-07-20 14:59:08'),
(1993,'COA-2025-181','Steel Filing Cabinet (4-Drawer)',3,2,'2025-05-13',22218.79,2,'Jose Ocampo',2,'Office of the Vice Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-05-14 09:00:00','2026-07-17 18:12:48'),
(1994,'COA-2019-200','Farm Tool Kit',9,5,'2019-06-04',33044.86,7,'Cecilia Reyes',NULL,'Treasury Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-06-06 09:00:00','2026-07-20 14:59:08'),
(1995,'COA-2019-201','Hand Tractor',9,1,'2019-01-29',38188.44,2,'Juan Santos',1,'Office of the Vice Mayor - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-01-29 09:00:00','2026-07-17 18:12:48'),
(1996,'COA-2019-202','Nebulizer Machine',8,1,'2019-11-17',32453.94,4,'Juan Aquino',1,'Human Resource Management Office - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-11-17 09:00:00','2026-07-20 14:59:08'),
(1997,'COA-2021-184','Base Radio Station',7,1,'2021-07-23',4543.31,5,'Carlos Domingo',1,'Budget Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-07-24 09:00:00','2026-07-20 12:47:01'),
(1998,'COA-2024-180','CCTV DVR/NVR Unit',7,1,'2024-04-14',41833.19,15,'Ricardo Aquino',NULL,'General Services Office - Main Office - Ground Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-04-16 09:00:00','2026-07-20 14:59:08'),
(1999,'COA-2025-182','Photocopier Machine (Multi-function)',4,1,'2025-08-27',44761.81,8,'Leonora Castillo',1,'Assessor\'s Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-08-28 09:00:00','2026-07-20 14:59:08'),
(2000,'COA-2023-217','CCTV Camera (Outdoor)',7,1,'2023-03-11',13847.28,16,'Juan Pascual',1,'Information and Communications Technology Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-03-12 09:00:00','2026-07-20 14:59:08'),
(2001,'COA-2022-184','Chainsaw (Rescue Type)',10,1,'2022-10-22',8014.69,4,'Carmen Santos',1,'Human Resource Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-10-24 09:00:00','2026-07-17 18:12:48'),
(2002,'COA-2020-151','Binding Machine',4,1,'2020-10-25',41434.58,4,'Ernesto Del Rosario',1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-10-25 09:00:00','2026-07-17 18:12:48'),
(2003,'COA-2022-185','Handheld Two-Way Radio',7,1,'2022-07-13',22959.87,11,'Luz Ocampo',1,'Municipal Planning and Development Office - Supply Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-07-16 09:00:00','2026-07-20 14:59:08'),
(2004,'COA-2023-218','Sprayer (Backpack, Motorized)',9,1,'2023-05-16',62854.41,16,'Eduardo Mendoza',NULL,'Information and Communications Technology Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2023-05-16 09:00:00','2026-07-20 14:59:08'),
(2005,'COA-2025-183','Paper Shredder (Heavy Duty)',4,1,'2025-09-13',24438.00,10,'Francisco Pascual',1,'Municipal Engineering Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-13 09:00:00','2026-07-20 14:59:08'),
(2006,'COA-2022-186','Binding Machine',4,1,'2022-11-22',17904.30,10,'Romeo Del Rosario',1,'Municipal Engineering Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2022-11-23 09:00:00','2026-07-17 18:12:48'),
(2007,'COA-2017-217','Base Radio Station',7,1,'2017-03-01',17060.87,9,'Norma Fernandez',1,'Civil Registrar\'s Office - Field Station','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-03-01 09:00:00','2026-07-17 18:12:48'),
(2008,'COA-2018-193','Concrete Mixer',6,1,'2018-08-31',762016.93,5,'Carmen Aquino',NULL,'Budget Office - Staff Room','UNSERVICEABLE','DISPOSED',NULL,NULL,'For disposal / condemnation per inspection report.',0,NULL,NULL,NULL,'2018-09-01 09:00:00','2026-07-20 12:47:01'),
(2009,'COA-2024-181','Grass Cutter (Riding Type)',6,1,'2024-05-17',1209023.84,16,'Gloria Rivera',1,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-20 09:00:00','2026-07-17 18:12:48'),
(2010,'COA-2020-152','Laser Printer (Monochrome)',2,1,'2020-08-08',25590.22,7,'Rodrigo Fernandez',NULL,'Treasury Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-08-11 09:00:00','2026-07-17 18:12:48'),
(2011,'COA-2018-194','Thermal Scanner',8,1,'2018-11-08',80828.75,4,'Divina Marquez',1,'Human Resource Management Office - Storage Room','SERVICEABLE','ASSIGNED',NULL,NULL,'Under warranty.',0,NULL,NULL,NULL,'2018-11-10 09:00:00','2026-07-17 18:12:48'),
(2012,'COA-2020-153','Autoclave Sterilizer',8,1,'2020-03-07',5893.93,10,'Carlos Cruz',1,'Municipal Engineering Office - Motor Pool / Garage','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-03-08 09:00:00','2026-07-20 14:59:08'),
(2013,'COA-2024-182','Desktop Computer Set (Core i5)',2,1,'2024-05-28',80329.14,15,'Divina Fernandez',NULL,'General Services Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2024-05-30 09:00:00','2026-07-17 18:12:48'),
(2014,'COA-2026-096','Laser Printer (Monochrome)',2,1,'2026-02-19',15567.67,13,'Eduardo Flores',1,'Municipal Social Welfare and Development Office - Staff Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-02-19 09:00:00','2026-07-20 14:59:08'),
(2015,'COA-2018-195','IP Desk Phone',7,1,'2018-09-10',39865.64,16,'Danilo Rivera',1,'Information and Communications Technology Office - Supply Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-09-11 09:00:00','2026-07-17 18:12:48'),
(2016,'COA-2018-196','24-Port Network Switch',2,1,'2018-08-02',70981.28,7,'Corazon Dela Cruz',1,'Treasury Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-08-02 09:00:00','2026-07-17 18:12:48'),
(2017,'COA-2020-154','Inflatable Rescue Boat',10,1,'2020-11-05',81149.12,8,NULL,NULL,'Assessor\'s Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2020-11-07 09:00:00','2026-07-20 14:59:08'),
(2018,'COA-2018-197','Farm Tool Kit',9,1,'2018-03-13',120730.08,1,NULL,NULL,'Office of the Mayor - Storage Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-03-16 09:00:00','2026-07-20 14:59:08'),
(2019,'COA-2017-218','Electric Kettle',1,1,'2017-12-14',12027.42,17,NULL,NULL,'Disaster Risk Reduction and Management Office - Motor Pool / Garage','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2017-12-15 09:00:00','2026-07-20 14:59:08'),
(2020,'COA-2025-184','Steel Locker Cabinet',3,2,'2025-09-08',26364.51,17,'Divina Garcia',2,'Disaster Risk Reduction and Management Office - Records Section','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2025-09-10 09:00:00','2026-07-20 14:59:08'),
(2021,'COA-2016-192','Steel Filing Cabinet (4-Drawer)',3,5,'2016-12-04',14311.41,13,'Eduardo Garcia',5,'Municipal Social Welfare and Development Office - Conference Room','REPAIRABLE','UNDER_MAINTENANCE',NULL,NULL,NULL,0,NULL,NULL,NULL,'2016-12-04 09:00:00','2026-07-20 14:59:08'),
(2022,'COA-2026-097','Multi-Purpose Van',5,1,'2026-04-04',1675116.32,13,'Imelda Castillo',1,'Municipal Social Welfare and Development Office - Reception Area','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2026-04-07 09:00:00','2026-07-17 18:12:48'),
(2023,'COA-2018-198','Water Tanker Truck',6,1,'2018-05-25',2975894.21,3,'Juan Del Rosario',1,'Sangguniang Bayan Office - Conference Room','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2018-05-26 09:00:00','2026-07-20 14:59:08'),
(2024,'COA-2019-203','Megaphone (Bullhorn)',7,1,'2019-05-17',6737.97,17,'Ramon Salazar',1,'Disaster Risk Reduction and Management Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-05-18 09:00:00','2026-07-17 18:12:48'),
(2025,'COA-2019-204','Binding Machine',4,1,'2019-08-18',63436.21,8,NULL,1,'Assessor\'s Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2019-08-19 09:00:00','2026-07-17 18:12:48'),
(2026,'COA-2021-185','PABX Telephone System',7,1,'2021-04-03',4463.92,10,'Teresa Del Rosario',1,'Municipal Engineering Office - Field Station','UNSERVICEABLE','DISPOSED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2021-04-05 09:00:00','2026-07-20 14:59:08'),
(2027,'COA-2020-155','Water Cooler/Dispenser',1,1,'2020-09-20',38674.75,16,'Teresa Mendoza',1,'Information and Communications Technology Office - Main Office - 2nd Floor','SERVICEABLE','ASSIGNED',NULL,NULL,'Donated unit.',0,NULL,NULL,NULL,'2020-09-20 09:00:00','2026-07-17 18:12:48'),
(2028,'COA-2020-156','Document Scanner',2,1,'2020-05-16',24344.89,17,'Alfredo Del Rosario',1,'Disaster Risk Reduction and Management Office - Records Section','SERVICEABLE','ASSIGNED',NULL,NULL,NULL,0,NULL,NULL,NULL,'2020-05-17 09:00:00','2026-07-17 18:12:48');

-- --------------------------------------------------------

--
-- Table structure for table `asset_history`
--

CREATE TABLE `asset_history` (
  `history_id` bigint(20) NOT NULL,
  `asset_id` int(11) NOT NULL,
  `event_type` enum('REGISTERED','ASSIGNED','TRANSFERRED','MAINTENANCE','DISPOSAL','ARCHIVED') NOT NULL,
  `from_office_id` int(11) DEFAULT NULL COMMENT 'Source office (transfers only)',
  `to_office_id` int(11) DEFAULT NULL COMMENT 'Destination office (transfers only)',
  `performed_by` int(11) NOT NULL COMMENT 'User who performed the action',
  `event_date` datetime NOT NULL DEFAULT current_timestamp(),
  `notes` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `asset_history`
--

INSERT INTO `asset_history` (`history_id`, `asset_id`, `event_type`, `from_office_id`, `to_office_id`, `performed_by`, `event_date`, `notes`) VALUES
(1,1,'TRANSFERRED',1,NULL,1,'2026-06-30 10:29:20',NULL),
(2,1,'TRANSFERRED',1,2,1,'2026-07-05 15:33:36','Transferred per memo #2026-045'),
(7,2,'REGISTERED',NULL,16,1,'2026-01-15 00:00:00','Asset registered: COA-2026-002 (backfilled)'),
(8,3,'REGISTERED',NULL,6,1,'2026-01-20 00:00:00','Asset registered: COA-2026-003 (backfilled)'),
(9,4,'REGISTERED',NULL,1,1,'2025-11-05 00:00:00','Asset registered: COA-2026-004 (backfilled)'),
(10,5,'REGISTERED',NULL,8,1,'2025-10-12 00:00:00','Asset registered: COA-2026-005 (backfilled)'),
(11,6,'REGISTERED',NULL,9,1,'2025-09-01 00:00:00','Asset registered: COA-2026-006 (backfilled)'),
(12,7,'REGISTERED',NULL,17,1,'2024-06-18 00:00:00','Asset registered: COA-2026-007 (backfilled)'),
(13,8,'REGISTERED',NULL,15,1,'2025-08-22 00:00:00','Asset registered: COA-2026-008 (backfilled)'),
(14,9,'REGISTERED',NULL,4,1,'2025-07-30 00:00:00','Asset registered: COA-2026-009 (backfilled)'),
(15,10,'REGISTERED',NULL,11,1,'2025-05-14 00:00:00','Asset registered: COA-2026-010 (backfilled)'),
(16,11,'REGISTERED',NULL,12,1,'2024-03-10 00:00:00','Asset registered: COA-2026-011 (backfilled)'),
(17,12,'REGISTERED',NULL,14,1,'2025-02-25 00:00:00','Asset registered: COA-2026-012 (backfilled)'),
(18,13,'REGISTERED',NULL,10,1,'2025-04-02 00:00:00','Asset registered: COA-2026-013 (backfilled)'),
(19,14,'REGISTERED',NULL,13,1,'2024-12-19 00:00:00','Asset registered: COA-2026-014 (backfilled)'),
(20,15,'REGISTERED',NULL,2,1,'2025-01-08 00:00:00','Asset registered: COA-2026-015 (backfilled)'),
(21,16,'REGISTERED',NULL,3,1,'2025-06-11 00:00:00','Asset registered: COA-2026-016 (backfilled)'),
(22,17,'REGISTERED',NULL,7,1,'2025-03-27 00:00:00','Asset registered: COA-2026-017 (backfilled)'),
(23,18,'REGISTERED',NULL,16,1,'2025-09-15 00:00:00','Asset registered: COA-2026-018 (backfilled)'),
(24,23,'REGISTERED',NULL,1,1,'2026-01-15 00:00:00','Asset registered: TEST-DEBUG-003 (backfilled)'),
(25,25,'REGISTERED',NULL,1,1,'2026-01-15 00:00:00','Asset registered: COA-2026-019 (backfilled)'),
(26,27,'REGISTERED',NULL,12,1,'2026-07-20 07:25:36','Asset registered: COA-2022-263'),
(27,28,'REGISTERED',NULL,1,1,'2026-07-20 07:57:40','Asset registered: COA-2026-020'),
(28,28,'TRANSFERRED',1,2,1,'2026-07-20 08:05:04','Transferred from Office of the Mayor to Office of the Vice Mayor'),
(29,29,'REGISTERED',NULL,1,2,'2026-07-20 09:19:21','Asset registered: COA-2026-021'),
(30,30,'REGISTERED',NULL,17,1,'2026-07-20 09:45:46','Asset registered: COA-2026-022'),
(31,25,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(32,36,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(33,39,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(34,40,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(35,45,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(36,49,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(37,54,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(38,55,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(39,58,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(40,59,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(41,62,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(42,63,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(43,67,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(44,69,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(45,77,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(46,79,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(47,87,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(48,99,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(49,101,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(50,102,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(51,108,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(52,113,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(53,114,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(54,119,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(55,122,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(56,126,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(57,141,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(58,147,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(59,150,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(60,153,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(61,159,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(62,160,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(63,167,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(64,170,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(65,171,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(66,183,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(67,188,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(68,205,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(69,207,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(70,212,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(71,223,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(72,233,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(73,234,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(74,239,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(75,248,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(76,250,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(77,253,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(78,262,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(79,265,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(80,266,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(81,267,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(82,268,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(83,269,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(84,270,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(85,271,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(86,273,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(87,275,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(88,278,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(89,279,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(90,290,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(91,293,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(92,299,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(93,301,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(94,303,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(95,304,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(96,307,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(97,314,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(98,319,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(99,322,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(100,323,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(101,327,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(102,332,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(103,333,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(104,348,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(105,352,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(106,360,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(107,362,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(108,371,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(109,374,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(110,379,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(111,381,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(112,388,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(113,389,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(114,390,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(115,403,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(116,410,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(117,413,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(118,425,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(119,442,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(120,444,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(121,447,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(122,459,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(123,470,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(124,479,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(125,488,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(126,490,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(127,491,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(128,495,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(129,504,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(130,505,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(131,507,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(132,512,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(133,517,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(134,522,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(135,523,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(136,525,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(137,528,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(138,532,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(139,538,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(140,546,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(141,553,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(142,561,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(143,563,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(144,579,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(145,583,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(146,603,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(147,609,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(148,617,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(149,620,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(150,621,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(151,625,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(152,626,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(153,627,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(154,634,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(155,641,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(156,644,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(157,646,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(158,647,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(159,648,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(160,650,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(161,651,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(162,656,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(163,657,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(164,661,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(165,663,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(166,671,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(167,679,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(168,680,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(169,688,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(170,696,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(171,702,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(172,704,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(173,706,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(174,712,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(175,718,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(176,724,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(177,725,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(178,730,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(179,733,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(180,736,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(181,737,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(182,743,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(183,744,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(184,754,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(185,757,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(186,760,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(187,765,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(188,766,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(189,769,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(190,784,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(191,785,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(192,786,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(193,793,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(194,796,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(195,802,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(196,813,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(197,816,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(198,817,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(199,821,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(200,824,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(201,826,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(202,827,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(203,828,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(204,844,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(205,846,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(206,851,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(207,854,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(208,856,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(209,860,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(210,864,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(211,865,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(212,882,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(213,890,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(214,894,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(215,898,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(216,911,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(217,918,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(218,926,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(219,941,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(220,943,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(221,949,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(222,950,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(223,955,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(224,958,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(225,970,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(226,987,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(227,993,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(228,994,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(229,995,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(230,1000,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(231,1003,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(232,1009,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(233,1016,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(234,1024,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(235,1032,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(236,1042,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(237,1061,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(238,1062,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(239,1071,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(240,1074,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(241,1076,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(242,1083,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(243,1091,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(244,1093,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(245,1097,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(246,1101,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(247,1104,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(248,1106,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(249,1107,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(250,1115,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(251,1116,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(252,1117,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(253,1118,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(254,1119,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(255,1128,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(256,1129,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(257,1132,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(258,1140,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(259,1141,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(260,1149,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(261,1152,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(262,1153,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(263,1162,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(264,1164,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(265,1166,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(266,1172,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(267,1173,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(268,1174,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(269,1175,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(270,1181,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(271,1199,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(272,1200,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(273,1204,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(274,1211,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(275,1216,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(276,1221,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(277,1224,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(278,1232,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(279,1235,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(280,1237,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(281,1240,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(282,1244,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(283,1246,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(284,1248,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(285,1252,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(286,1256,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(287,1260,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(288,1264,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(289,1265,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(290,1274,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(291,1283,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(292,1286,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(293,1290,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(294,1295,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(295,1296,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(296,1307,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(297,1308,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(298,1309,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(299,1314,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(300,1319,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(301,1321,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(302,1322,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(303,1327,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(304,1328,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(305,1333,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(306,1335,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(307,1337,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(308,1347,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(309,1348,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(310,1349,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(311,1354,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(312,1359,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(313,1363,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(314,1367,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(315,1369,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(316,1370,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(317,1372,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(318,1378,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(319,1381,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(320,1385,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(321,1387,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(322,1394,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(323,1403,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(324,1409,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(325,1413,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(326,1418,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(327,1420,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(328,1425,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(329,1429,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(330,1436,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(331,1440,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(332,1456,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(333,1459,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(334,1463,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(335,1467,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(336,1473,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(337,1480,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(338,1481,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(339,1494,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(340,1495,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(341,1496,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(342,1503,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(343,1511,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(344,1514,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(345,1528,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(346,1542,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(347,1550,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(348,1567,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(349,1568,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(350,1570,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(351,1575,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(352,1578,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(353,1579,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(354,1582,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(355,1583,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(356,1584,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(357,1592,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(358,1593,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(359,1601,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(360,1605,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(361,1608,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(362,1611,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(363,1614,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(364,1616,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(365,1620,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(366,1624,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(367,1626,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(368,1628,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(369,1633,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(370,1638,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(371,1642,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(372,1648,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(373,1649,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(374,1655,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(375,1656,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(376,1659,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(377,1676,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(378,1678,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(379,1679,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(380,1685,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(381,1688,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(382,1709,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(383,1712,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(384,1716,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(385,1720,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(386,1721,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(387,1722,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(388,1723,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(389,1727,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(390,1729,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(391,1730,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(392,1731,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(393,1733,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(394,1737,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(395,1739,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(396,1745,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(397,1750,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(398,1752,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(399,1758,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(400,1760,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(401,1770,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(402,1771,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(403,1779,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(404,1785,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(405,1786,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(406,1787,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(407,1794,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(408,1807,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(409,1820,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(410,1826,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(411,1836,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(412,1843,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(413,1845,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(414,1851,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(415,1856,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(416,1858,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(417,1865,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(418,1867,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(419,1888,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(420,1891,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(421,1893,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(422,1898,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(423,1907,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(424,1909,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(425,1921,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(426,1940,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(427,1942,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(428,1943,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(429,1947,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(430,1948,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(431,1952,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(432,1955,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(433,1956,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(434,1961,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(435,1964,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(436,1969,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(437,1970,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(438,1971,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(439,1972,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(440,1974,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(441,1982,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(442,1984,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(443,1994,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(444,1996,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(445,1999,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(446,2000,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(447,2003,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(448,2004,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(449,2014,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(450,2017,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(451,2018,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(452,2020,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(453,2021,'MAINTENANCE',NULL,NULL,1,'2026-07-20 13:40:23','Flagged repairable, maintenance record auto-created'),
(542,2,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(543,32,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(544,34,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(545,44,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(546,56,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(547,57,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(548,66,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(549,72,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(550,83,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(551,98,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(552,104,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(553,105,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(554,106,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(555,110,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(556,118,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(557,124,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(558,132,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(559,136,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(560,151,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(561,158,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(562,164,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(563,165,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(564,168,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(565,197,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(566,198,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(567,211,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(568,215,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(569,217,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(570,225,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(571,241,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(572,245,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(573,255,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(574,256,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(575,259,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(576,282,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(577,287,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(578,311,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(579,313,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(580,334,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(581,335,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(582,338,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(583,342,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(584,353,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(585,356,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(586,366,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(587,384,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(588,386,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(589,393,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(590,411,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(591,415,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(592,419,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(593,421,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(594,423,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(595,441,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(596,450,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(597,452,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(598,455,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(599,468,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(600,472,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(601,477,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(602,483,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(603,487,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(604,492,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(605,494,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(606,498,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(607,508,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(608,520,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(609,530,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(610,533,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(611,539,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(612,540,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(613,555,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(614,562,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(615,570,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(616,574,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(617,585,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(618,589,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(619,590,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(620,596,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(621,599,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(622,616,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(623,623,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(624,639,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(625,645,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(626,654,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(627,655,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(628,659,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(629,660,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(630,662,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(631,665,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(632,666,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(633,670,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(634,675,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(635,677,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(636,683,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(637,684,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(638,689,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(639,699,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(640,700,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(641,707,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(642,708,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(643,717,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(644,738,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(645,746,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(646,748,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(647,758,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(648,764,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(649,771,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(650,772,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(651,774,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(652,776,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(653,794,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(654,798,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(655,800,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(656,805,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(657,810,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(658,812,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(659,825,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(660,838,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(661,849,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(662,862,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(663,868,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(664,869,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(665,895,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(666,900,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(667,906,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(668,914,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(669,919,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(670,930,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(671,948,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(672,962,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(673,968,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(674,969,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(675,971,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(676,974,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(677,978,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(678,980,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(679,982,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(680,986,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(681,999,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(682,1012,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(683,1035,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(684,1041,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(685,1055,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(686,1057,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(687,1058,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(688,1066,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(689,1068,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(690,1072,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(691,1087,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(692,1089,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(693,1096,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(694,1109,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(695,1122,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(696,1137,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(697,1139,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(698,1144,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(699,1150,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(700,1151,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(701,1155,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(702,1176,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(703,1183,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(704,1185,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(705,1188,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(706,1196,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(707,1198,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(708,1202,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(709,1214,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(710,1219,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(711,1228,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(712,1234,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(713,1247,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(714,1253,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(715,1267,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(716,1276,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(717,1281,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(718,1282,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(719,1284,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(720,1285,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(721,1288,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(722,1291,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(723,1310,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(724,1318,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(725,1329,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(726,1331,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(727,1340,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(728,1342,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(729,1346,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(730,1351,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(731,1353,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(732,1355,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(733,1366,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(734,1376,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(735,1386,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(736,1389,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(737,1393,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(738,1395,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(739,1397,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(740,1401,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(741,1408,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(742,1412,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(743,1434,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(744,1453,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(745,1475,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(746,1487,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(747,1499,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(748,1512,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(749,1518,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(750,1519,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(751,1521,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(752,1522,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(753,1527,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(754,1529,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(755,1532,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(756,1537,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(757,1543,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(758,1545,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(759,1547,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(760,1551,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(761,1559,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(762,1560,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(763,1569,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(764,1600,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(765,1607,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(766,1610,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(767,1621,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(768,1629,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(769,1641,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(770,1643,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(771,1646,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(772,1650,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(773,1657,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(774,1670,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(775,1672,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(776,1682,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(777,1691,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(778,1694,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(779,1699,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(780,1703,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(781,1704,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(782,1708,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(783,1717,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(784,1724,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(785,1728,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(786,1734,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(787,1738,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(788,1743,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(789,1748,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(790,1755,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(791,1766,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(792,1768,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(793,1778,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(794,1780,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(795,1781,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(796,1804,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(797,1812,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(798,1818,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(799,1822,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(800,1829,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(801,1831,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(802,1837,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(803,1838,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(804,1839,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(805,1842,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(806,1846,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(807,1847,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(808,1848,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(809,1854,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(810,1881,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(811,1889,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(812,1910,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(813,1912,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(814,1913,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(815,1918,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(816,1924,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(817,1926,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(818,1933,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(819,1937,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(820,1938,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(821,1951,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(822,1959,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(823,1963,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(824,1965,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(825,1978,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(826,1981,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(827,2008,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(828,2012,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created'),
(829,2026,'DISPOSAL',NULL,NULL,1,'2026-07-20 13:40:23','Flagged unserviceable, disposal record auto-created');

-- --------------------------------------------------------

--
-- Table structure for table `audit_logs`
--

CREATE TABLE `audit_logs` (
  `log_id` bigint(20) NOT NULL,
  `user_id` int(11) NOT NULL,
  `action` varchar(100) NOT NULL COMMENT 'e.g., ASSET_CREATED, ASSET_TRANSFERRED, MAINTENANCE_LOGGED, USER_LOGIN',
  `module` varchar(50) NOT NULL COMMENT 'e.g., Inventory, Maintenance, Disposal, Users',
  `target_id` bigint(20) DEFAULT NULL,
  `target_type` varchar(50) DEFAULT NULL COMMENT 'e.g., asset, maintenance, disposal, user',
  `details` text DEFAULT NULL COMMENT 'Additional details or changed values',
  `ip_address` varchar(45) DEFAULT NULL COMMENT 'IPv4 or IPv6 address of the user session',
  `logged_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `audit_logs`
--

INSERT INTO `audit_logs` (`log_id`, `user_id`, `action`, `module`, `target_id`, `target_type`, `details`, `ip_address`, `logged_at`) VALUES
(1, 1, 'CATEGORY_CREATED', 'Categories', 1, 'category', 'Appliances', NULL, '2026-06-30 10:16:33'),
(2, 1, 'ASSET_CREATED', 'Assets', 1, 'asset', 'Created asset: COA-2026-001', NULL, '2026-06-30 10:16:33'),
(3, 1, 'HISTORY_CREATED', 'AssetHistory', 1, 'asset_history', 'Event: TRANSFERRED', NULL, '2026-06-30 10:29:20'),
(4, 1, 'AI_RECOMMENDATION_GENERATED', 'Assets', 2, 'asset', 'Generated AI recommendation for COA-2026-002: MONITOR', NULL, '2026-07-03 12:39:59'),
(5, 1, 'DISPOSAL_CREATED', 'Disposal', 1, 'disposal', 'Disposal for asset: COA-2026-011', NULL, '2026-07-03 15:59:19'),
(6, 1, 'AI_RECOMMENDATION_GENERATED', 'Assets', 2, 'asset', 'Generated AI recommendation for COA-2026-002: MONITOR', NULL, '2026-07-03 16:06:55'),
(7, 1, 'AI_RECOMMENDATION_GENERATED', 'Assets', 2, 'asset', 'Generated AI recommendation for COA-2026-002: MAINTAIN', NULL, '2026-07-03 17:58:14'),
(8, 1, 'MAINTENANCE_CREATED', 'Maintenance', 1, 'maintenance', 'Maintenance for asset: COA-2026-009', NULL, '2026-07-03 18:20:21'),
(9, 1, 'USER_CREATED', 'Users', 3, 'user', 'Created: test_staff2', NULL, '2026-07-03 22:47:10'),
(10, 1, 'USER_UPDATED', 'Users', 3, 'user', 'Updated: test_staff2', NULL, '2026-07-03 22:47:23'),
(11, 1, 'USER_DELETED', 'Users', 3, 'user', 'Deleted: test_staff2', NULL, '2026-07-03 22:47:23'),
(12, 1, 'USER_UPDATED', 'Users', 2, 'user', 'Updated: ict_staff', NULL, '2026-07-03 22:58:50'),
(13, 1, 'USER_UPDATED', 'Users', 2, 'user', 'Updated: ict_staff', NULL, '2026-07-03 22:58:53'),
(14, 1, 'ASSET_UPDATED', 'Assets', 1, 'asset', 'Updated asset: COA-2026-001', NULL, '2026-07-05 15:09:29'),
(15, 1, 'ASSET_CREATED', 'Assets', 23, 'asset', 'Created asset: TEST-DEBUG-003', NULL, '2026-07-05 15:18:15'),
(16, 1, 'ASSET_CREATED', 'Assets', 25, 'asset', 'Created asset: COA-2026-019', NULL, '2026-07-05 15:32:13'),
(17, 1, 'ASSET_DELETED', 'Assets', 1, 'asset', 'Deleted: COA-2026-001', NULL, '2026-07-05 15:32:39'),
(18, 1, 'HISTORY_CREATED', 'AssetHistory', 2, 'asset_history', 'Event: TRANSFERRED', NULL, '2026-07-05 15:33:36'),
(19, 1, 'AI_RECOMMENDATION_GENERATED', 'Assets', 25, 'asset', 'Generated AI recommendation for COA-2026-019: MAINTAIN', NULL, '2026-07-05 20:27:00'),
(20, 1, 'DISPOSAL_UPDATED', 'Disposal', 1, 'disposal', 'Updated disposal for asset: COA-2026-011', NULL, '2026-07-05 20:28:24'),
(21, 1, 'AI_RECOMMENDATION_GENERATED', 'Assets', 23, 'asset', 'Generated AI recommendation for TEST-DEBUG-003: MAINTAIN', NULL, '2026-07-05 21:17:10'),
(22, 1, 'DISPOSAL_CREATED', 'Disposal', 3, 'disposal', 'Disposal for asset: COA-2026-001', NULL, '2026-07-05 22:08:13'),
(23, 1, 'ASSET_UPDATED', 'Assets', 25, 'asset', 'Updated asset: COA-2026-019', NULL, '2026-07-05 22:40:33'),
(24, 1, 'MAINTENANCE_UPDATED', 'Maintenance', 2, 'maintenance', 'Updated maintenance for asset: COA-2026-019', NULL, '2026-07-05 22:41:13'),
(25, 1, 'AI_RECOMMENDATION_GENERATED', 'Assets', 3, 'asset', 'Generated AI recommendation for COA-2026-003: MAINTAIN', NULL, '2026-07-05 22:41:45'),
(26, 1, 'ASSET_UPDATED', 'Assets', 2, 'asset', 'Updated asset: COA-2026-002', NULL, '2026-07-05 22:46:33'),
(27, 1, 'ASSET_UPDATED', 'Assets', 2, 'asset', 'Updated asset: COA-2026-002', NULL, '2026-07-05 22:46:57'),
(28, 1, 'ASSET_UPDATED', 'Assets', 2, 'asset', 'Updated asset: COA-2026-002', NULL, '2026-07-05 22:50:15'),
(29, 1, 'DISPOSAL_UPDATED', 'Disposal', 5, 'disposal', 'Updated disposal for asset: COA-2026-002', NULL, '2026-07-05 22:51:17'),
(30, 1, 'AI_RECOMMENDATION_GENERATED', 'Assets', 2, 'asset', 'Generated AI recommendation for COA-2026-002: REVIEW_FOR_DISPOSAL', NULL, '2026-07-05 22:51:33'),
(31, 1, 'ASSET_CREATED', 'Assets', 26, 'asset', 'Created asset: HIST-TEST-001', NULL, '2026-07-05 23:03:07'),
(32, 1, 'ASSET_UPDATED', 'Assets', 26, 'asset', 'Updated asset: HIST-TEST-001', NULL, '2026-07-05 23:03:07'),
(33, 1, 'MAINTENANCE_CREATED', 'Maintenance', 3, 'maintenance', 'Maintenance for asset: HIST-TEST-001', NULL, '2026-07-05 23:03:08'),
(34, 1, 'ASSET_UPDATED', 'Assets', 26, 'asset', 'Updated asset: HIST-TEST-001', NULL, '2026-07-05 23:03:08');

-- --------------------------------------------------------

--
-- Table structure for table `audit_log_digests`
--

CREATE TABLE `audit_log_digests` (
  `digest_id` bigint(20) NOT NULL,
  `digest` text NOT NULL,
  `covered_entries` int(11) NOT NULL,
  `generated_at` datetime NOT NULL DEFAULT current_timestamp(),
  `generated_by_system` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `audit_log_digests`
--

INSERT INTO `audit_log_digests` (`digest_id`, `digest`, `covered_entries`, `generated_at`, `generated_by_system`) VALUES
(1, 'The system recorded about eight actions over the past few days, primarily focused on asset management. Activities included creating new assets, categories, and records for maintenance and disposal, along with generating several AI recommendations for assets. It\'s worth noting that multiple actions, including asset creation and several AI recommendation generations, occurred during the very early morning hours, outside of typical business operations.', 8, '2026-07-03 18:21:38', 1),
(2, 'The system logged about 19 actions over the past few days, mainly involving asset creations, updates, and AI recommendations in the Assets module, along with user management in the Users module. All activity was performed by the \'admin\' user. A significant amount of recent activity occurred outside normal business hours, particularly late on July 5th and early on July 4th. On July 4th, the \'admin\' user created, updated, and then immediately deleted a \'test_staff2\' account within seconds, which might indicate a test or cleanup operation.', 18, '2026-07-05 20:18:27', 1);

-- --------------------------------------------------------

--
-- Table structure for table `categories`
--

CREATE TABLE `categories` (
  `category_id` int(11) NOT NULL,
  `category_name` varchar(100) NOT NULL COMMENT 'e.g., ICT Equipment, Furniture, Appliance',
  `description` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `categories`
--

INSERT INTO `categories` (`category_id`, `category_name`, `description`) VALUES
(1, 'Appliances', ''),
(2, 'ICT Equipment', 'Computers, printers, and networking equipment'),
(3, 'Office Furniture', 'Desks, chairs, cabinets, and fixtures'),
(4, 'Office Equipment', 'Non-ICT machines used for office operations'),
(5, 'Motor Vehicle', 'Service vehicles and transport equipment'),
(6, 'Heavy Equipment', 'Backhoes, bulldozers, rollers, and other heavy machinery'),
(7, 'Communication Equipment', 'Radios, CCTV, telephone systems, and public-address equipment'),
(8, 'Medical Equipment', 'Clinical and first-aid equipment for municipal health services'),
(9, 'Agricultural Equipment', 'Farm tools and machinery for municipal agriculture support'),
(10, 'Disaster & Rescue Equipment', 'Emergency response and rescue equipment for DRRM operations');

-- --------------------------------------------------------

--
-- Table structure for table `deleted_assets`
--

CREATE TABLE `deleted_assets` (
  `deleted_asset_id` bigint(20) NOT NULL,
  `asset_id` bigint(20) NOT NULL,
  `property_number` varchar(50) NOT NULL,
  `description` varchar(255) NOT NULL,
  `category_id` bigint(20) NOT NULL,
  `category_name` varchar(100) NOT NULL COMMENT 'Snapshot of category name at deletion',
  `quantity` int(11) NOT NULL,
  `acquisition_date` date NOT NULL,
  `unit_value` decimal(12,2) NOT NULL,
  `office_id` bigint(20) NOT NULL,
  `office_name` varchar(100) NOT NULL COMMENT 'Snapshot of office name at deletion',
  `accountable_person_name` varchar(150) DEFAULT NULL COMMENT 'Snapshot of accountable person name',
  `location` varchar(150) NOT NULL,
  `condition` enum('SERVICEABLE','REPAIRABLE','UNSERVICEABLE') NOT NULL,
  `lifecycle_status` varchar(30) NOT NULL,
  `qr_code_path` varchar(255) DEFAULT NULL,
  `sha256_hash` varchar(64) DEFAULT NULL,
  `remarks` text DEFAULT NULL,
  `original_created_at` datetime NOT NULL COMMENT 'created_at from the assets row',
  `original_updated_at` datetime NOT NULL COMMENT 'updated_at from the assets row',
  `deleted_by_user_id` bigint(20) NOT NULL,
  `deleted_by_username` varchar(50) NOT NULL COMMENT 'Snapshot of username at deletion',
  `delete_reason` text DEFAULT NULL COMMENT 'Reason entered by the user',
  `deleted_at` datetime NOT NULL DEFAULT current_timestamp(),
  `accountable_person_id` bigint(20) DEFAULT NULL,
  `asset_condition` varchar(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Archive of soft-deleted asset records with full snapshots';

--
-- Dumping data for table `deleted_assets`
--

INSERT INTO `deleted_assets` (`deleted_asset_id`, `asset_id`, `property_number`, `description`, `category_id`, `category_name`, `quantity`, `acquisition_date`, `unit_value`, `office_id`, `office_name`, `accountable_person_name`, `location`, `condition`, `lifecycle_status`, `qr_code_path`, `sha256_hash`, `remarks`, `original_created_at`, `original_updated_at`, `deleted_by_user_id`, `deleted_by_username`, `delete_reason`, `deleted_at`, `accountable_person_id`, `asset_condition`) VALUES
(1, 1, 'COA-2026-001', 'Dell Latitude 5440 Laptop', 1, 'Appliances', 1, '2026-01-15', 45000.00, 1, 'Office of the Mayor', 'Juan Dela Cruz', 'GSO Office - 2nd Floor', 'SERVICEABLE', 'ASSIGNED', NULL, NULL, 'Assigned to IT division', '2026-06-30 10:16:33', '2026-07-05 15:09:29', 1, 'admin', 'Duplicate entry created by mistake', '2026-07-05 15:32:39', NULL, '');

-- --------------------------------------------------------

--
-- Table structure for table `deleted_disposal`
--

CREATE TABLE `deleted_disposal` (
  `deleted_disposal_id` bigint(20) NOT NULL,
  `disposal_id` bigint(20) NOT NULL,
  `asset_id` bigint(20) NOT NULL,
  `property_number` varchar(50) NOT NULL COMMENT 'Snapshot of property number',
  `asset_description` varchar(255) NOT NULL COMMENT 'Snapshot of asset description',
  `reason` text NOT NULL,
  `inspection_findings` text NOT NULL,
  `recommended_method` varchar(20) NOT NULL,
  `disposal_status` varchar(20) NOT NULL,
  `inspection_date` date NOT NULL,
  `approved_by_user_id` bigint(20) DEFAULT NULL,
  `approved_by_name` varchar(100) DEFAULT NULL COMMENT 'Snapshot of approver name',
  `appraised_value` decimal(12,2) DEFAULT NULL,
  `or_number` varchar(50) DEFAULT NULL,
  `amount` decimal(12,2) DEFAULT NULL,
  `recorded_by_user_id` bigint(20) NOT NULL,
  `recorded_by_name` varchar(100) NOT NULL COMMENT 'Snapshot of recorder name',
  `original_created_at` datetime NOT NULL,
  `deleted_by_user_id` bigint(20) NOT NULL,
  `deleted_by_username` varchar(50) NOT NULL,
  `delete_reason` text DEFAULT NULL,
  `deleted_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Archive of soft-deleted disposal ledger records';

-- --------------------------------------------------------

--
-- Table structure for table `deleted_maintenance`
--

CREATE TABLE `deleted_maintenance` (
  `deleted_maintenance_id` bigint(20) NOT NULL,
  `maintenance_id` bigint(20) NOT NULL,
  `asset_id` bigint(20) NOT NULL,
  `property_number` varchar(50) NOT NULL COMMENT 'Snapshot of property number',
  `asset_description` varchar(255) NOT NULL COMMENT 'Snapshot of asset description',
  `maintenance_type` varchar(20) NOT NULL,
  `findings` text NOT NULL,
  `actions_taken` text NOT NULL,
  `assigned_to_user_id` bigint(20) DEFAULT NULL,
  `assigned_to_name` varchar(100) DEFAULT NULL COMMENT 'Snapshot of assigned technician name',
  `maintenance_date` date NOT NULL,
  `cost` decimal(10,2) DEFAULT NULL,
  `status` varchar(20) NOT NULL,
  `recorded_by_user_id` bigint(20) NOT NULL,
  `recorded_by_name` varchar(100) NOT NULL COMMENT 'Snapshot of recorder name',
  `original_created_at` datetime NOT NULL,
  `deleted_by_user_id` bigint(20) NOT NULL,
  `deleted_by_username` varchar(50) NOT NULL,
  `delete_reason` text DEFAULT NULL,
  `deleted_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Archive of soft-deleted maintenance ledger records';

-- --------------------------------------------------------

--
-- Table structure for table `device_records`
--

CREATE TABLE `device_records` (
  `device_id` bigint(20) NOT NULL,
  `equipment_id` int(11) NOT NULL,
  `item_code` varchar(50) DEFAULT NULL,
  `serial_number` varchar(100) DEFAULT NULL,
  `model` varchar(100) DEFAULT NULL,
  `amount_value` decimal(12,2) DEFAULT NULL COMMENT 'Acquisition unit value in PHP',
  `acquisition_date` date DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `disposal_justifications`
--

CREATE TABLE `disposal_justifications` (
  `justification_id` bigint(20) NOT NULL,
  `disposal_id` bigint(20) NOT NULL,
  `justification` text NOT NULL,
  `generated_at` datetime NOT NULL DEFAULT current_timestamp(),
  `generated_by_system` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `disposal_justifications`
--

INSERT INTO `disposal_justifications` (`justification_id`, `disposal_id`, `justification`, `generated_at`, `generated_by_system`) VALUES
(1, 1, 'The Refrigerator 7 cu.ft., bearing inventory tag COA-2026-011 and assigned to the Municipal Health Office, is being considered for disposal due to a critical failure of its compressor unit. This renders the appliance non-functional, and internal assessment indicates that repair would not be economically viable relative to the cost of a replacement unit.\n\nAn inspection conducted on 2026-06-15 confirmed that the compressor unit no longer builds pressure, consistent with a refrigerant leak. The unit has been completely non-functional for over three months. Additionally, the cabinet shows visible rust damage on the lower panel. While the asset is relatively new at 2.3 years and has no prior repair history, the extensive nature of the compressor failure, which is the core functional component, suggests that the cost of professional repair, including parts and labor for refrigerant system restoration, would likely approach or exceed its original unit value of PHP 16,500.00.\n\nGiven the irreparable damage to the primary functional component and the presence of refrigerants, which require specialized handling, the recommended disposal method is destruction. This method is appropriate to prevent potential unauthorized resale or repurposing of a permanently non-functional unit and ensures that all components, particularly hazardous materials like refrigerants, are managed in accordance with environmental regulations and applicable government property disposal regulations.', '2026-07-03 16:00:48', 1);

-- --------------------------------------------------------

--
-- Table structure for table `disposal_ledger`
--

CREATE TABLE `disposal_ledger` (
  `disposal_id` bigint(20) NOT NULL,
  `asset_id` int(11) NOT NULL,
  `reason` text NOT NULL,
  `inspection_findings` text NOT NULL,
  `recommended_method` enum('AUCTION','DONATION','TRANSFER') NOT NULL,
  `disposal_status` enum('PENDING','APPROVED','COMPLETED') NOT NULL DEFAULT 'PENDING',
  `inspection_date` date NOT NULL,
  `approved_by` varchar(150) DEFAULT NULL COMMENT 'Name of approving authority',
  `appraised_value` decimal(12,2) DEFAULT NULL,
  `or_number` varchar(50) DEFAULT NULL,
  `amount` decimal(12,2) DEFAULT NULL,
  `recorded_by` int(11) NOT NULL,
  `is_deleted` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'Soft delete flag',
  `deleted_at` datetime DEFAULT NULL,
  `deleted_by` int(11) DEFAULT NULL COMMENT 'User who soft-deleted this record (ref: users)',
  `delete_reason` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `disposal_ledger`
--

INSERT INTO `disposal_ledger` (`disposal_id`, `asset_id`, `reason`, `inspection_findings`, `recommended_method`, `disposal_status`, `inspection_date`, `approved_by`, `appraised_value`, `or_number`, `amount`, `recorded_by`, `is_deleted`, `deleted_at`, `deleted_by`, `delete_reason`, `created_at`, `updated_at`) VALUES
(1,11,'Refrigerator compressor has failed and repair is not economically viable relative to replacement cost.','Compressor unit no longer builds pressure; refrigerant has leaked out; unit has been non-functional for over 3 months. Cabinet shows rust damage on lower panel.','AUCTION','PENDING','2026-06-15',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-03 15:59:19','2026-07-19 11:32:44'),
(5,2,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-05',NULL,NULL,NULL,35000.00,1,0,NULL,NULL,NULL,'2026-07-05 22:50:15','2026-07-19 11:32:42'),
(7,32,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(8,34,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(9,44,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(10,56,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(11,57,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(12,66,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(13,72,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(14,83,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(15,98,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(16,104,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(17,105,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(18,106,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(19,110,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(20,118,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(21,124,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(22,132,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(23,136,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(24,151,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(25,158,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(26,164,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(27,165,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(28,168,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(29,197,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(30,198,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(31,211,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(32,215,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(33,217,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(34,225,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(35,241,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(36,245,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(37,255,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(38,256,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(39,259,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(40,282,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(41,287,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(42,311,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(43,313,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(44,334,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(45,335,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(46,338,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(47,342,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(48,353,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(49,356,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(50,366,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(51,384,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(52,386,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(53,393,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(54,411,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(55,415,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(56,419,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(57,421,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(58,423,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(59,441,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(60,450,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(61,452,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(62,455,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(63,468,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(64,472,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(65,477,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(66,483,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(67,487,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(68,492,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(69,494,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(70,498,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(71,508,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(72,520,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(73,530,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(74,533,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(75,539,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(76,540,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(77,555,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(78,562,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(79,570,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(80,574,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(81,585,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(82,589,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(83,590,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(84,596,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(85,599,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(86,616,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(87,623,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(88,639,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(89,645,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(90,654,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(91,655,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(92,659,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(93,660,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(94,662,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(95,665,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(96,666,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(97,670,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(98,675,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(99,677,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(100,683,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(101,684,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(102,689,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(103,699,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(104,700,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(105,707,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(106,708,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(107,717,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(108,738,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(109,746,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(110,748,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(111,758,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(112,764,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(113,771,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(114,772,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(115,774,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(116,776,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(117,794,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(118,798,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(119,800,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(120,805,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(121,810,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(122,812,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(123,825,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(124,838,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(125,849,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(126,862,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(127,868,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(128,869,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(129,895,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(130,900,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(131,906,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(132,914,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(133,919,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(134,930,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(135,948,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(136,962,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(137,968,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(138,969,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(139,971,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(140,974,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(141,978,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(142,980,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(143,982,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(144,986,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(145,999,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(146,1012,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(147,1035,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(148,1041,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(149,1055,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(150,1057,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(151,1058,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(152,1066,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(153,1068,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(154,1072,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(155,1087,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(156,1089,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(157,1096,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(158,1109,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(159,1122,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(160,1137,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(161,1139,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(162,1144,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(163,1150,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(164,1151,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(165,1155,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(166,1176,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(167,1183,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(168,1185,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(169,1188,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(170,1196,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(171,1198,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(172,1202,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(173,1214,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(174,1219,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(175,1228,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(176,1234,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(177,1247,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(178,1253,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(179,1267,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(180,1276,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(181,1281,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(182,1282,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(183,1284,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(184,1285,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(185,1288,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(186,1291,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(187,1310,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(188,1318,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(189,1329,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(190,1331,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(191,1340,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(192,1342,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(193,1346,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(194,1351,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(195,1353,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(196,1355,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(197,1366,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(198,1376,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(199,1386,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(200,1389,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(201,1393,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(202,1395,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(203,1397,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(204,1401,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(205,1408,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(206,1412,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(207,1434,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(208,1453,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(209,1475,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(210,1487,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(211,1499,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(212,1512,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(213,1518,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(214,1519,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(215,1521,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(216,1522,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(217,1527,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(218,1529,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(219,1532,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(220,1537,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(221,1543,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(222,1545,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(223,1547,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(224,1551,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(225,1559,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(226,1560,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(227,1569,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(228,1600,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(229,1607,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(230,1610,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(231,1621,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(232,1629,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(233,1641,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(234,1643,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(235,1646,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(236,1650,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(237,1657,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(238,1670,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(239,1672,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(240,1682,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(241,1691,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(242,1694,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(243,1699,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(244,1703,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(245,1704,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(246,1708,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(247,1717,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(248,1724,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(249,1728,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(250,1734,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(251,1738,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(252,1743,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(253,1748,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(254,1755,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(255,1766,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(256,1768,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(257,1778,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(258,1780,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(259,1781,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(260,1804,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(261,1812,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(262,1818,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(263,1822,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(264,1829,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(265,1831,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(266,1837,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(267,1838,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(268,1839,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(269,1842,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(270,1846,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(271,1847,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(272,1848,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(273,1854,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(274,1881,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(275,1889,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(276,1910,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(277,1912,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(278,1913,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(279,1918,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(280,1924,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(281,1926,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(282,1933,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(283,1937,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(284,1938,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(285,1951,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(286,1959,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(287,1963,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(288,1965,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(289,1978,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(290,1981,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(291,2008,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(292,2012,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23'),
(293,2026,'Asset is unserviceable and flagged for disposal','Auto-generated from asset condition change','AUCTION','PENDING','2026-07-20',NULL,NULL,NULL,NULL,1,0,NULL,NULL,NULL,'2026-07-20 13:40:23','2026-07-20 13:40:23');

-- --------------------------------------------------------

--
-- Table structure for table `equipment_records`
--

CREATE TABLE `equipment_records` (
  `equipment_id` int(11) NOT NULL,
  `type` varchar(50) NOT NULL COMMENT 'Hardware, Software, Peripherals, etc.',
  `equipment_type` varchar(100) NOT NULL COMMENT 'Desktop Computer, Laptop, Printer, etc.',
  `item_code` varchar(50) NOT NULL COMMENT 'ICT-assigned item code',
  `article` varchar(255) NOT NULL COMMENT 'Common name / article of the equipment',
  `office` varchar(255) NOT NULL COMMENT 'Assigned office name',
  `location` varchar(255) NOT NULL COMMENT 'Physical location',
  `description` text DEFAULT NULL,
  `accountable_person` varchar(150) NOT NULL,
  `accountable_person_phone` varchar(50) DEFAULT NULL,
  `accountable_person_email` varchar(150) DEFAULT NULL,
  `device_count` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `idempotency_keys`
--
-- Backs IdempotencyService/IdempotencyFilter: a write request claims a row via
-- INSERT (the composite primary key is what makes concurrent duplicate claims
-- fail atomically), then the row is either updated with the cached response
-- (2xx) or deleted (non-2xx, so the same key can be retried).
--

CREATE TABLE `idempotency_keys` (
  `idempotency_key` varchar(255) NOT NULL,
  `request_method` varchar(10) NOT NULL,
  `request_path` varchar(255) NOT NULL,
  `username` varchar(100) NOT NULL,
  `response_status` int(11) DEFAULT NULL,
  `response_body` longtext DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `completed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`idempotency_key`,`request_method`,`request_path`,`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `maintenance_ledger`
--

CREATE TABLE `maintenance_ledger` (
  `maintenance_id` bigint(20) NOT NULL,
  `asset_id` int(11) NOT NULL,
  `maintenance_type` enum('PREVENTIVE','CORRECTIVE','REPAIR') NOT NULL,
  `findings` text NOT NULL,
  `actions_taken` text NOT NULL,
  `assigned_to` varchar(150) DEFAULT NULL COMMENT 'Name of technician or responsible person',
  `maintenance_date` date NOT NULL,
  `cost` decimal(10,2) DEFAULT NULL COMMENT 'Cost in PHP; NULL if no cost incurred',
  `status` enum('COMPLETED','ONGOING','SCHEDULED') NOT NULL,
  `recorded_by` int(11) NOT NULL COMMENT 'User who logged the record',
  `is_deleted` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'Soft delete flag',
  `deleted_at` datetime DEFAULT NULL,
  `deleted_by` int(11) DEFAULT NULL COMMENT 'User who soft-deleted this record (ref: users)',
  `delete_reason` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `maintenance_ledger`
--

INSERT INTO `maintenance_ledger` (`maintenance_id`, `asset_id`, `maintenance_type`, `findings`, `actions_taken`, `assigned_to`, `maintenance_date`, `cost`, `status`, `recorded_by`, `is_deleted`, `deleted_at`, `deleted_by`, `delete_reason`, `created_at`, `updated_at`) VALUES
(1,9,'REPAIR','The projector displays a faint image and the lamp flickers intermittently before shutting off after about 5 minutes of use. The cooling fan also makes a grinding noise, suggesting a bearing issue.','Replaced the projector lamp module and cleaned the internal cooling fan and vents. Ran a 30-minute burn-in test with no flickering or shutdowns observed. Fan noise resolved after cleaning.','Juan Dela Cruz','2026-06-20',4500.00,'COMPLETED',1,0,NULL,NULL,NULL,'2026-07-03 18:20:21','2026-07-19 04:45:27'),
(2,25,'CORRECTIVE','Asset flagged as repairable — requires maintenance','Pending review and assignment',NULL,'2026-07-05',13000.00,'SCHEDULED',1,0,NULL,NULL,NULL,'2026-07-05 22:40:33','2026-07-20 07:07:23'),
(4,36,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(5,39,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(6,40,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(7,45,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(8,49,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(9,54,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(10,55,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(11,58,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(12,59,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(13,62,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(14,63,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(15,67,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(16,69,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(17,77,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(18,79,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(19,87,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(20,99,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(21,101,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(22,102,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(23,108,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(24,113,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(25,114,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(26,119,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(27,122,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(28,126,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(29,141,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(30,147,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(31,150,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(32,153,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(33,159,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(34,160,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(35,167,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(36,170,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(37,171,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(38,183,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(39,188,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(40,205,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(41,207,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(42,212,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(43,223,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(44,233,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(45,234,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(46,239,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(47,248,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(48,250,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(49,253,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(50,262,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(51,265,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(52,266,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(53,267,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(54,268,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(55,269,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(56,270,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(57,271,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(58,273,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(59,275,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(60,278,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(61,279,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(62,290,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(63,293,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(64,299,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(65,301,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(66,303,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(67,304,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(68,307,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(69,314,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(70,319,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(71,322,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(72,323,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(73,327,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(74,332,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(75,333,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(76,348,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(77,352,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(78,360,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(79,362,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(80,371,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(81,374,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(82,379,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(83,381,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(84,388,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(85,389,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(86,390,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(87,403,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(88,410,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(89,413,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(90,425,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(91,442,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(92,444,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(93,447,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(94,459,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(95,470,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(96,479,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(97,488,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(98,490,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(99,491,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(100,495,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(101,504,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(102,505,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(103,507,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(104,512,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(105,517,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(106,522,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(107,523,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(108,525,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(109,528,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(110,532,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(111,538,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(112,546,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(113,553,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(114,561,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(115,563,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(116,579,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(117,583,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(118,603,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(119,609,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(120,617,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(121,620,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(122,621,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(123,625,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(124,626,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(125,627,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(126,634,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(127,641,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(128,644,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(129,646,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(130,647,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(131,648,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(132,650,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(133,651,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(134,656,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(135,657,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(136,661,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(137,663,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(138,671,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(139,679,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(140,680,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(141,688,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(142,696,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(143,702,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(144,704,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(145,706,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(146,712,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(147,718,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(148,724,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(149,725,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(150,730,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(151,733,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(152,736,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(153,737,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(154,743,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(155,744,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(156,754,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(157,757,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(158,760,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(159,765,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(160,766,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(161,769,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(162,784,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(163,785,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(164,786,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(165,793,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(166,796,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(167,802,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(168,813,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(169,816,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(170,817,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(171,821,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(172,824,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(173,826,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(174,827,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(175,828,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(176,844,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(177,846,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(178,851,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(179,854,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(180,856,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(181,860,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(182,864,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(183,865,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(184,882,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(185,890,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(186,894,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(187,898,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(188,911,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(189,918,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(190,926,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(191,941,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(192,943,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(193,949,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(194,950,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(195,955,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(196,958,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(197,970,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(198,987,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(199,993,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(200,994,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(201,995,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(202,1000,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(203,1003,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(204,1009,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(205,1016,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(206,1024,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(207,1032,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(208,1042,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(209,1061,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(210,1062,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(211,1071,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(212,1074,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(213,1076,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(214,1083,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(215,1091,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(216,1093,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(217,1097,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(218,1101,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(219,1104,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(220,1106,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(221,1107,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(222,1115,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(223,1116,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(224,1117,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(225,1118,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(226,1119,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(227,1128,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(228,1129,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(229,1132,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(230,1140,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(231,1141,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(232,1149,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(233,1152,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(234,1153,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(235,1162,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(236,1164,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(237,1166,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(238,1172,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(239,1173,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(240,1174,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(241,1175,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(242,1181,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(243,1199,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(244,1200,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(245,1204,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(246,1211,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(247,1216,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(248,1221,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(249,1224,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(250,1232,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(251,1235,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(252,1237,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(253,1240,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(254,1244,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(255,1246,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(256,1248,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(257,1252,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(258,1256,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(259,1260,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(260,1264,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(261,1265,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(262,1274,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(263,1283,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(264,1286,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(265,1290,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(266,1295,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(267,1296,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(268,1307,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(269,1308,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(270,1309,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(271,1314,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(272,1319,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(273,1321,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(274,1322,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(275,1327,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(276,1328,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(277,1333,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(278,1335,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(279,1337,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(280,1347,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(281,1348,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(282,1349,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(283,1354,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(284,1359,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(285,1363,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(286,1367,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(287,1369,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(288,1370,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(289,1372,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(290,1378,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(291,1381,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(292,1385,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(293,1387,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(294,1394,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(295,1403,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(296,1409,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(297,1413,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(298,1418,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(299,1420,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(300,1425,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(301,1429,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(302,1436,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(303,1440,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(304,1456,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(305,1459,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(306,1463,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(307,1467,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(308,1473,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(309,1480,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(310,1481,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(311,1494,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(312,1495,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(313,1496,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(314,1503,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(315,1511,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(316,1514,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(317,1528,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(318,1542,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(319,1550,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(320,1567,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(321,1568,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(322,1570,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(323,1575,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(324,1578,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(325,1579,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(326,1582,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(327,1583,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(328,1584,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(329,1592,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(330,1593,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(331,1601,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(332,1605,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(333,1608,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(334,1611,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(335,1614,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(336,1616,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(337,1620,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(338,1624,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(339,1626,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(340,1628,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(341,1633,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(342,1638,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(343,1642,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(344,1648,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(345,1649,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(346,1655,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(347,1656,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(348,1659,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(349,1676,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(350,1678,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(351,1679,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(352,1685,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(353,1688,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(354,1709,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(355,1712,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(356,1716,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(357,1720,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(358,1721,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(359,1722,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(360,1723,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(361,1727,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(362,1729,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(363,1730,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(364,1731,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(365,1733,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(366,1737,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(367,1739,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(368,1745,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(369,1750,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(370,1752,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(371,1758,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(372,1760,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(373,1770,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(374,1771,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(375,1779,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(376,1785,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(377,1786,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(378,1787,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(379,1794,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(380,1807,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(381,1820,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(382,1826,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(383,1836,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(384,1843,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(385,1845,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(386,1851,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(387,1856,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(388,1858,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(389,1865,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(390,1867,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(391,1888,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(392,1891,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(393,1893,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(394,1898,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(395,1907,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(396,1909,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(397,1921,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(398,1940,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(399,1942,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(400,1943,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(401,1947,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(402,1948,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(403,1952,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(404,1955,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(405,1956,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(406,1961,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(407,1964,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(408,1969,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(409,1970,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(410,1971,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(411,1972,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(412,1974,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(413,1982,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(414,1984,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(415,1994,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(416,1996,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(417,1999,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(418,2000,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(419,2003,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(420,2004,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(421,2014,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(422,2017,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(423,2018,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(424,2020,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22'),
(425,2021,'REPAIR','Asset flagged as repairable - requires maintenance','Pending review and assignment',NULL,'2026-07-20',NULL,'ONGOING',1,0,NULL,NULL,NULL,'2026-07-20 13:40:22','2026-07-20 13:40:22');

-- --------------------------------------------------------

--
-- Table structure for table `maintenance_summaries`
--

CREATE TABLE `maintenance_summaries` (
  `summary_id` bigint(20) NOT NULL,
  `maintenance_id` bigint(20) NOT NULL,
  `summary` text NOT NULL,
  `generated_at` datetime NOT NULL DEFAULT current_timestamp(),
  `generated_by_system` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `maintenance_summaries`
--

INSERT INTO `maintenance_summaries` (`summary_id`, `maintenance_id`, `summary`, `generated_at`, `generated_by_system`) VALUES
(1, 1, 'Flickering image and fan noise resolved by replacing lamp and cleaning fan.', '2026-07-03 18:21:18', 1),
(2, 2, 'Repair needed, but specific issue is unclear; actions pending.', '2026-07-06 10:13:15', 1);

-- --------------------------------------------------------

--
-- Table structure for table `offices`
--

CREATE TABLE `offices` (
  `office_id` int(11) NOT NULL,
  `office_name` varchar(100) NOT NULL,
  `head_user_id` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `offices`
--

INSERT INTO `offices` (`office_id`, `office_name`, `head_user_id`, `created_at`) VALUES
(1, 'Office of the Mayor', NULL, '2026-06-30 10:12:59'),
(2, 'Office of the Vice Mayor', NULL, '2026-06-30 10:12:59'),
(3, 'Sangguniang Bayan Office', NULL, '2026-06-30 10:12:59'),
(4, 'Human Resource Management Office', NULL, '2026-06-30 10:12:59'),
(5, 'Budget Office', NULL, '2026-06-30 10:12:59'),
(6, 'Accounting Office', NULL, '2026-06-30 10:12:59'),
(7, 'Treasury Office', NULL, '2026-06-30 10:12:59'),
(8, 'Assessor\'s Office', NULL, '2026-06-30 10:12:59'),
(9, 'Civil Registrar\'s Office', NULL, '2026-06-30 10:12:59'),
(10, 'Municipal Engineering Office', NULL, '2026-06-30 10:12:59'),
(11, 'Municipal Planning and Development Office', NULL, '2026-06-30 10:12:59'),
(12, 'Municipal Health Office', NULL, '2026-06-30 10:12:59'),
(13, 'Municipal Social Welfare and Development Office', NULL, '2026-06-30 10:12:59'),
(14, 'Municipal Agriculture Office', NULL, '2026-06-30 10:12:59'),
(15, 'General Services Office', NULL, '2026-06-30 10:12:59'),
(16, 'Information and Communications Technology Office', NULL, '2026-06-30 10:12:59'),
(17, 'Disaster Risk Reduction and Management Office', NULL, '2026-06-30 10:12:59');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `user_id` int(11) NOT NULL,
  `username` varchar(50) NOT NULL,
  `password_hash` varchar(255) NOT NULL COMMENT 'BCrypt-hashed password',
  `full_name` varchar(100) NOT NULL,
  `role` varchar(20) NOT NULL,
  `office_id` int(11) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `failed_login_attempts` int(11) NOT NULL DEFAULT 0,
  `account_locked_until` datetime DEFAULT NULL,
  `privacy_acknowledged_at` datetime DEFAULT NULL COMMENT 'Set when the user acknowledges the Data Privacy Notice; NULL means not yet acknowledged',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `email` varchar(255) DEFAULT NULL,
  `must_change_password` tinyint(1) NOT NULL DEFAULT 1,
  `token_version` int(11) NOT NULL DEFAULT 0 COMMENT 'Bumped to invalidate outstanding JWTs (password change/reset)',
  `two_factor_enabled` tinyint(1) NOT NULL DEFAULT 1 COMMENT 'Email OTP required to complete login; off for admin/ict_staff fixture accounts',
  `login_otp_hash` varchar(255) DEFAULT NULL,
  `login_otp_expires_at` datetime DEFAULT NULL,
  `login_otp_attempts` int(11) NOT NULL DEFAULT 0,
  `last_password_reset_at` datetime DEFAULT NULL,
  `password_reset_otp_hash` varchar(255) DEFAULT NULL,
  `password_reset_otp_expires_at` datetime DEFAULT NULL,
  `password_reset_otp_attempts` int(11) NOT NULL DEFAULT 0,
  UNIQUE KEY `uq_users_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`user_id`, `username`, `password_hash`, `full_name`, `role`, `office_id`, `is_active`, `failed_login_attempts`, `account_locked_until`, `privacy_acknowledged_at`, `created_at`, `email`, `must_change_password`, `token_version`, `two_factor_enabled`, `last_password_reset_at`, `password_reset_otp_hash`, `password_reset_otp_expires_at`, `password_reset_otp_attempts`, `login_otp_hash`, `login_otp_expires_at`, `login_otp_attempts`) VALUES
(1,'admin','$2a$10$d5H.7W.oNNjZKUZ4l8TnleDh1ZduRgyilUkopaavnGn2hGvgkDqAe','Administrator','ADMIN',NULL,1,0,NULL,'2026-07-20 11:41:27','2026-06-30 10:12:59','admin@sanjosegso.local',0,0,0,NULL,'$2a$10$NuR6V80vjy8x2gQTHz9oQ.5kxiUb5FuOqRHssaWxLuQR6MtfBuVby','2026-07-20 11:58:25',0,NULL,NULL,0),
(2,'ict_staff','$2a$10$pM6E.Yi60dVz1pP74b/kmOlvNbdGWP5FTuqNB3yivEVusiwaGG/7K','ICT Officer','STAFF',NULL,1,0,NULL,NULL,'2026-06-30 10:12:59','ict.staff@sanjosegso.local',0,0,0,NULL,NULL,NULL,0,NULL,NULL,0),
(5,'KevinRoyZamoraNuque','$2a$10$PDXRnymWzcKvD.348GFYU.N3SdYJ7XYUgMszO5gox8Y/NNE/m.lcC','Kevin Roy Zamora Nuque','STAFF',10,1,0,NULL,'2026-07-20 11:43:46','2026-07-20 11:42:08','nuquekevinroyzamora@gmail.com',0,3,1,'2026-07-20 12:30:01',NULL,NULL,0,NULL,NULL,0),
(6,'Kzzzz','$2a$10$oAvTM7vI8/.faSkh6rTP/eNRTBYyPckRcPpBcffp/KMGXwZr/ejKe','Kz Kz','STAFF',NULL,1,0,NULL,'2026-07-20 12:27:31','2026-07-20 12:03:30','itzzaphkielasphalt@gmail.com',0,1,1,NULL,NULL,NULL,0,NULL,NULL,0);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `ai_recommendations`
--
ALTER TABLE `ai_recommendations`
  ADD PRIMARY KEY (`recommendation_id`),
  ADD KEY `idx_air_asset_id` (`asset_id`),
  ADD KEY `idx_air_generated_at` (`generated_at`);

--
-- Indexes for table `assets`
--
ALTER TABLE `assets`
  ADD PRIMARY KEY (`asset_id`),
  ADD UNIQUE KEY `uq_assets_prop_no` (`property_number`),
  ADD KEY `fk_assets_deleted_by` (`deleted_by`),
  ADD KEY `idx_assets_category` (`category_id`),
  ADD KEY `idx_assets_office` (`office_id`),
  ADD KEY `idx_assets_condition` (`condition`),
  ADD KEY `idx_assets_lifecycle` (`lifecycle_status`),
  ADD KEY `idx_assets_accountable` (`accountable_person`),
  ADD KEY `idx_assets_is_deleted` (`is_deleted`);

--
-- Indexes for table `asset_history`
--
ALTER TABLE `asset_history`
  ADD PRIMARY KEY (`history_id`),
  ADD KEY `fk_ah_from_office` (`from_office_id`),
  ADD KEY `fk_ah_to_office` (`to_office_id`),
  ADD KEY `fk_ah_performed_by` (`performed_by`),
  ADD KEY `idx_ah_asset_id` (`asset_id`),
  ADD KEY `idx_ah_event_date` (`event_date`);

--
-- Indexes for table `audit_logs`
--
ALTER TABLE `audit_logs`
  ADD PRIMARY KEY (`log_id`),
  ADD KEY `idx_al_user_id` (`user_id`),
  ADD KEY `idx_al_module` (`module`),
  ADD KEY `idx_al_logged_at` (`logged_at`);

--
-- Indexes for table `audit_log_digests`
--
ALTER TABLE `audit_log_digests`
  ADD PRIMARY KEY (`digest_id`);

--
-- Indexes for table `categories`
--
ALTER TABLE `categories`
  ADD PRIMARY KEY (`category_id`),
  ADD UNIQUE KEY `uq_categories_name` (`category_name`);

--
-- Indexes for table `deleted_assets`
--
ALTER TABLE `deleted_assets`
  ADD PRIMARY KEY (`deleted_asset_id`),
  ADD KEY `idx_da_asset_id` (`asset_id`),
  ADD KEY `idx_da_property_no` (`property_number`),
  ADD KEY `idx_da_deleted_at` (`deleted_at`),
  ADD KEY `idx_da_deleted_by` (`deleted_by_user_id`);

--
-- Indexes for table `deleted_disposal`
--
ALTER TABLE `deleted_disposal`
  ADD PRIMARY KEY (`deleted_disposal_id`),
  ADD KEY `idx_dd_disposal_id` (`disposal_id`),
  ADD KEY `idx_dd_asset_id` (`asset_id`),
  ADD KEY `idx_dd_deleted_at` (`deleted_at`),
  ADD KEY `idx_dd_deleted_by` (`deleted_by_user_id`);

--
-- Indexes for table `deleted_maintenance`
--
ALTER TABLE `deleted_maintenance`
  ADD PRIMARY KEY (`deleted_maintenance_id`),
  ADD KEY `idx_dm_maintenance_id` (`maintenance_id`),
  ADD KEY `idx_dm_asset_id` (`asset_id`),
  ADD KEY `idx_dm_deleted_at` (`deleted_at`),
  ADD KEY `idx_dm_deleted_by` (`deleted_by_user_id`);

--
-- Indexes for table `device_records`
--
ALTER TABLE `device_records`
  ADD PRIMARY KEY (`device_id`),
  ADD KEY `idx_dr_equipment_id` (`equipment_id`),
  ADD KEY `idx_dr_serial_number` (`serial_number`);

--
-- Indexes for table `disposal_justifications`
--
ALTER TABLE `disposal_justifications`
  ADD PRIMARY KEY (`justification_id`),
  ADD KEY `idx_dj_disposal_id` (`disposal_id`);

--
-- Indexes for table `disposal_ledger`
--
ALTER TABLE `disposal_ledger`
  ADD PRIMARY KEY (`disposal_id`),
  ADD KEY `fk_dl_recorded_by` (`recorded_by`),
  ADD KEY `fk_dl_deleted_by` (`deleted_by`),
  ADD KEY `idx_dl_asset_id` (`asset_id`),
  ADD KEY `idx_dl_status` (`disposal_status`),
  ADD KEY `idx_dl_is_deleted` (`is_deleted`);

--
-- Indexes for table `equipment_records`
--
ALTER TABLE `equipment_records`
  ADD PRIMARY KEY (`equipment_id`),
  ADD KEY `idx_eq_type` (`type`),
  ADD KEY `idx_eq_office` (`office`),
  ADD KEY `idx_eq_created_at` (`created_at`);

--
-- Indexes for table `maintenance_ledger`
--
ALTER TABLE `maintenance_ledger`
  ADD PRIMARY KEY (`maintenance_id`),
  ADD KEY `fk_ml_recorded_by` (`recorded_by`),
  ADD KEY `fk_ml_deleted_by` (`deleted_by`),
  ADD KEY `idx_ml_asset_id` (`asset_id`),
  ADD KEY `idx_ml_maintenance_date` (`maintenance_date`),
  ADD KEY `idx_ml_type` (`maintenance_type`),
  ADD KEY `idx_ml_is_deleted` (`is_deleted`);

--
-- Indexes for table `maintenance_summaries`
--
ALTER TABLE `maintenance_summaries`
  ADD PRIMARY KEY (`summary_id`),
  ADD KEY `idx_ms_maintenance_id` (`maintenance_id`);

--
-- Indexes for table `offices`
--
ALTER TABLE `offices`
  ADD PRIMARY KEY (`office_id`),
  ADD UNIQUE KEY `uq_offices_name` (`office_name`),
  ADD KEY `fk_offices_head` (`head_user_id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`user_id`),
  ADD UNIQUE KEY `uq_users_uname` (`username`),
  ADD KEY `fk_users_office` (`office_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `ai_recommendations`
--
ALTER TABLE `ai_recommendations`
  MODIFY `recommendation_id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `assets`
--
ALTER TABLE `assets`
  MODIFY `asset_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=27;

--
-- AUTO_INCREMENT for table `asset_history`
--
ALTER TABLE `asset_history`
  MODIFY `history_id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=26;

--
-- AUTO_INCREMENT for table `audit_logs`
--
ALTER TABLE `audit_logs`
  MODIFY `log_id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=35;

--
-- AUTO_INCREMENT for table `audit_log_digests`
--
ALTER TABLE `audit_log_digests`
  MODIFY `digest_id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `categories`
--
ALTER TABLE `categories`
  MODIFY `category_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `deleted_assets`
--
ALTER TABLE `deleted_assets`
  MODIFY `deleted_asset_id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `deleted_disposal`
--
ALTER TABLE `deleted_disposal`
  MODIFY `deleted_disposal_id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `deleted_maintenance`
--
ALTER TABLE `deleted_maintenance`
  MODIFY `deleted_maintenance_id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `device_records`
--
ALTER TABLE `device_records`
  MODIFY `device_id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `disposal_justifications`
--
ALTER TABLE `disposal_justifications`
  MODIFY `justification_id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `disposal_ledger`
--
ALTER TABLE `disposal_ledger`
  MODIFY `disposal_id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `equipment_records`
--
ALTER TABLE `equipment_records`
  MODIFY `equipment_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `maintenance_ledger`
--
ALTER TABLE `maintenance_ledger`
  MODIFY `maintenance_id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `maintenance_summaries`
--
ALTER TABLE `maintenance_summaries`
  MODIFY `summary_id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `offices`
--
ALTER TABLE `offices`
  MODIFY `office_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=18;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `user_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `ai_recommendations`
--
ALTER TABLE `ai_recommendations`
  ADD CONSTRAINT `fk_air_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `assets`
--
ALTER TABLE `assets`
  ADD CONSTRAINT `fk_assets_category` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_assets_deleted_by` FOREIGN KEY (`deleted_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_assets_office` FOREIGN KEY (`office_id`) REFERENCES `offices` (`office_id`) ON UPDATE CASCADE;

--
-- Constraints for table `asset_history`
--
ALTER TABLE `asset_history`
  ADD CONSTRAINT `fk_ah_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_ah_from_office` FOREIGN KEY (`from_office_id`) REFERENCES `offices` (`office_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_ah_performed_by` FOREIGN KEY (`performed_by`) REFERENCES `users` (`user_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_ah_to_office` FOREIGN KEY (`to_office_id`) REFERENCES `offices` (`office_id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `audit_logs`
--
ALTER TABLE `audit_logs`
  ADD CONSTRAINT `fk_al_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON UPDATE CASCADE;

--
-- Constraints for table `device_records`
--
ALTER TABLE `device_records`
  ADD CONSTRAINT `fk_devices_equipment` FOREIGN KEY (`equipment_id`) REFERENCES `equipment_records` (`equipment_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `disposal_justifications`
--
ALTER TABLE `disposal_justifications`
  ADD CONSTRAINT `fk_dj_disposal` FOREIGN KEY (`disposal_id`) REFERENCES `disposal_ledger` (`disposal_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `disposal_ledger`
--
ALTER TABLE `disposal_ledger`
  ADD CONSTRAINT `fk_dl_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_dl_deleted_by` FOREIGN KEY (`deleted_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_dl_recorded_by` FOREIGN KEY (`recorded_by`) REFERENCES `users` (`user_id`) ON UPDATE CASCADE;

--
-- Constraints for table `maintenance_ledger`
--
ALTER TABLE `maintenance_ledger`
  ADD CONSTRAINT `fk_ml_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_ml_deleted_by` FOREIGN KEY (`deleted_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_ml_recorded_by` FOREIGN KEY (`recorded_by`) REFERENCES `users` (`user_id`) ON UPDATE CASCADE;

--
-- Constraints for table `maintenance_summaries`
--
ALTER TABLE `maintenance_summaries`
  ADD CONSTRAINT `fk_ms_maintenance` FOREIGN KEY (`maintenance_id`) REFERENCES `maintenance_ledger` (`maintenance_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `offices`
--
ALTER TABLE `offices`
  ADD CONSTRAINT `fk_offices_head` FOREIGN KEY (`head_user_id`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `users`
--
ALTER TABLE `users`
  ADD CONSTRAINT `fk_users_office` FOREIGN KEY (`office_id`) REFERENCES `offices` (`office_id`) ON DELETE SET NULL ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
