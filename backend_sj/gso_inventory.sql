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
(1, 'COA-2026-001', 'Dell Latitude 5440 Laptop', 1, 1, '2026-01-15', 45000.00, 1, 'Juan Dela Cruz', 1, 'GSO Office - 2nd Floor', 'SERVICEABLE', 'ASSIGNED', NULL, NULL, 'Assigned to IT division', 1, '2026-07-05 15:32:39', 1, 'Duplicate entry created by mistake', '2026-06-30 10:16:33', '2026-07-05 15:32:39'),
(2, 'COA-2026-002', 'Dell Latitude 5440 Laptop', 2, 1, '2026-01-15', 52000.00, 16, 'Juan Dela Cruz', 1, 'Information and Communications Technology Office', 'UNSERVICEABLE', 'DISPOSED', NULL, NULL, 'Assigned to ICT support staff', 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-05 22:50:15'),
(3, 'COA-2026-003', 'HP LaserJet Pro M404dn Printer', 2, 1, '2026-01-20', 18500.00, 6, 'Maria Santos', 1, 'Accounting Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(4, 'COA-2026-004', 'Executive Office Desk', 3, 1, '2025-11-05', 9500.00, 1, 'Hon. Mayor', 1, 'Office of the Mayor', 'SERVICEABLE', 'ASSIGNED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(5, 'COA-2026-005', '4-Drawer Steel Filing Cabinet', 3, 3, '2025-10-12', 6200.00, 8, NULL, 3, 'Assessor\'s Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(6, 'COA-2026-006', 'Canon imageRUNNER 2625i Photocopier', 4, 1, '2025-09-01', 95000.00, 9, NULL, 1, 'Civil Registrar\'s Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, 'Shared unit for records division', 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(7, 'COA-2026-007', 'Toyota Hilux Service Pickup', 5, 1, '2024-06-18', 1250000.00, 17, 'Pedro Ramos', 1, 'Disaster Risk Reduction and Management Office', 'SERVICEABLE', 'ASSIGNED', NULL, NULL, 'Plate No. SJH-1234', 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(8, 'COA-2026-008', 'Split-Type Air Conditioner 2HP', 1, 1, '2025-08-22', 38000.00, 15, NULL, 1, 'General Services Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(9, 'COA-2026-009', 'Epson EB-X49 Projector', 2, 1, '2025-07-30', 32000.00, 4, NULL, 1, 'Human Resource Management Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(10, 'COA-2026-010', 'Ergonomic Office Chair', 3, 10, '2025-05-14', 4500.00, 11, NULL, 9, 'Municipal Planning and Development Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, 'Bulk purchase of 10 units', 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(11, 'COA-2026-011', 'Refrigerator 7 cu.ft.', 1, 1, '2024-03-10', 16500.00, 12, NULL, 1, 'Municipal Health Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(12, 'COA-2026-012', 'Acer Veriton Desktop Computer Set', 2, 5, '2025-02-25', 34000.00, 14, NULL, 4, 'Municipal Agriculture Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, 'Set includes monitor, keyboard, mouse', 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(13, 'COA-2026-013', 'Yamaha Brush Cutter', 4, 2, '2025-04-02', 12500.00, 10, 'Roberto Cruz', 2, 'Municipal Engineering Office', 'SERVICEABLE', 'ASSIGNED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(14, 'COA-2026-014', 'Honda Generator 5.5kVA', 4, 1, '2024-12-19', 68000.00, 13, NULL, 1, 'Municipal Social Welfare and Development Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(15, 'COA-2026-015', 'Conference Table 10-Seater', 3, 1, '2025-01-08', 22000.00, 2, NULL, 1, 'Office of the Vice Mayor', 'SERVICEABLE', 'REGISTERED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(16, 'COA-2026-016', 'Wireless Microphone System', 2, 1, '2025-06-11', 14500.00, 3, NULL, 1, 'Sangguniang Bayan Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, 'Used for session hall', 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(17, 'COA-2026-017', 'Cash Counting Machine', 4, 1, '2025-03-27', 27500.00, 7, 'Elena Fernandez', 1, 'Treasury Office', 'SERVICEABLE', 'ASSIGNED', NULL, NULL, NULL, 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(18, 'COA-2026-018', 'TP-Link 24-Port Network Switch', 2, 2, '2025-09-15', 8200.00, 16, NULL, 2, 'Information and Communications Technology Office', 'SERVICEABLE', 'REGISTERED', NULL, NULL, 'Server room rack unit', 0, NULL, NULL, NULL, '2026-07-03 08:37:25', '2026-07-03 08:37:25'),
(23, 'TEST-DEBUG-003', 'Dell Latitude 5440 Laptop', 1, 1, '2026-01-15', 45000.00, 1, 'Juan Dela Cruz', 1, 'GSO Office - 2nd Floor', 'SERVICEABLE', 'REGISTERED', NULL, NULL, 'Brand new unit', 0, NULL, NULL, NULL, '2026-07-05 15:18:15', '2026-07-05 15:18:15'),
(25, 'COA-2026-019', 'Dell Latitude 5440 Laptop', 1, 1, '2026-01-15', 45000.00, 1, 'Juan Dela Cruz', 1, 'Office of the Mayor', 'REPAIRABLE', 'UNDER_MAINTENANCE', NULL, NULL, 'Brand new unit', 0, NULL, NULL, NULL, '2026-07-05 15:32:13', '2026-07-05 22:40:33');

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
(1, 1, 'TRANSFERRED', 1, 5, 1, '2026-06-30 10:29:20', NULL),
(2, 1, 'TRANSFERRED', 1, 2, 1, '2026-07-05 15:33:36', 'Transferred per memo #2026-045'),
(7, 2, 'REGISTERED', NULL, 16, 1, '2026-01-15 00:00:00', 'Asset registered: COA-2026-002 (backfilled)'),
(8, 3, 'REGISTERED', NULL, 6, 1, '2026-01-20 00:00:00', 'Asset registered: COA-2026-003 (backfilled)'),
(9, 4, 'REGISTERED', NULL, 1, 1, '2025-11-05 00:00:00', 'Asset registered: COA-2026-004 (backfilled)'),
(10, 5, 'REGISTERED', NULL, 8, 1, '2025-10-12 00:00:00', 'Asset registered: COA-2026-005 (backfilled)'),
(11, 6, 'REGISTERED', NULL, 9, 1, '2025-09-01 00:00:00', 'Asset registered: COA-2026-006 (backfilled)'),
(12, 7, 'REGISTERED', NULL, 17, 1, '2024-06-18 00:00:00', 'Asset registered: COA-2026-007 (backfilled)'),
(13, 8, 'REGISTERED', NULL, 15, 1, '2025-08-22 00:00:00', 'Asset registered: COA-2026-008 (backfilled)'),
(14, 9, 'REGISTERED', NULL, 4, 1, '2025-07-30 00:00:00', 'Asset registered: COA-2026-009 (backfilled)'),
(15, 10, 'REGISTERED', NULL, 11, 1, '2025-05-14 00:00:00', 'Asset registered: COA-2026-010 (backfilled)'),
(16, 11, 'REGISTERED', NULL, 12, 1, '2024-03-10 00:00:00', 'Asset registered: COA-2026-011 (backfilled)'),
(17, 12, 'REGISTERED', NULL, 14, 1, '2025-02-25 00:00:00', 'Asset registered: COA-2026-012 (backfilled)'),
(18, 13, 'REGISTERED', NULL, 10, 1, '2025-04-02 00:00:00', 'Asset registered: COA-2026-013 (backfilled)'),
(19, 14, 'REGISTERED', NULL, 13, 1, '2024-12-19 00:00:00', 'Asset registered: COA-2026-014 (backfilled)'),
(20, 15, 'REGISTERED', NULL, 2, 1, '2025-01-08 00:00:00', 'Asset registered: COA-2026-015 (backfilled)'),
(21, 16, 'REGISTERED', NULL, 3, 1, '2025-06-11 00:00:00', 'Asset registered: COA-2026-016 (backfilled)'),
(22, 17, 'REGISTERED', NULL, 7, 1, '2025-03-27 00:00:00', 'Asset registered: COA-2026-017 (backfilled)'),
(23, 18, 'REGISTERED', NULL, 16, 1, '2025-09-15 00:00:00', 'Asset registered: COA-2026-018 (backfilled)'),
(24, 23, 'REGISTERED', NULL, 1, 1, '2026-01-15 00:00:00', 'Asset registered: TEST-DEBUG-003 (backfilled)'),
(25, 25, 'REGISTERED', NULL, 1, 1, '2026-01-15 00:00:00', 'Asset registered: COA-2026-019 (backfilled)');

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
(5, 'Motor Vehicle', 'Service vehicles and transport equipment');

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
  `accountable_person_name` varchar(150) NOT NULL COMMENT 'Snapshot of accountable person name',
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
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `disposal_ledger`
--

INSERT INTO `disposal_ledger` (`disposal_id`, `asset_id`, `reason`, `inspection_findings`, `recommended_method`, `disposal_status`, `inspection_date`, `approved_by`, `appraised_value`, `or_number`, `amount`, `recorded_by`, `is_deleted`, `deleted_at`, `deleted_by`, `delete_reason`, `created_at`) VALUES
(1, 11, 'Refrigerator compressor has failed and repair is not economically viable relative to replacement cost.', 'Compressor unit no longer builds pressure; refrigerant has leaked out; unit has been non-functional for over 3 months. Cabinet shows rust damage on lower panel.', 'AUCTION', 'PENDING', '2026-06-15', NULL, NULL, NULL, NULL, 1, 0, NULL, NULL, NULL, '2026-07-03 15:59:19'),
(5, 2, 'Asset is unserviceable and flagged for disposal', 'Auto-generated from asset condition change', 'AUCTION', 'PENDING', '2026-07-05', NULL, NULL, NULL, 35000.00, 1, 0, NULL, NULL, NULL, '2026-07-05 22:50:15');

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
-- Backs IdempotencyFilter/IdempotencyService: a client-supplied Idempotency-Key
-- (sent on POST create requests) claims a row here so a retried/double-tapped
-- request replays the original response instead of creating a duplicate record.
-- Plain infra table, not tied to a stored procedure like the domain tables above.
--

CREATE TABLE `idempotency_keys` (
  `idempotency_key` varchar(255) NOT NULL,
  `request_method` varchar(10) NOT NULL,
  `request_path` varchar(255) NOT NULL,
  `username` varchar(50) NOT NULL,
  `response_status` int(11) DEFAULT NULL,
  `response_body` longtext DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `completed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`idempotency_key`)
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
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `maintenance_ledger`
--

INSERT INTO `maintenance_ledger` (`maintenance_id`, `asset_id`, `maintenance_type`, `findings`, `actions_taken`, `assigned_to`, `maintenance_date`, `cost`, `status`, `recorded_by`, `is_deleted`, `deleted_at`, `deleted_by`, `delete_reason`, `created_at`) VALUES
(1, 9, 'REPAIR', 'The projector displays a faint image and the lamp flickers intermittently before shutting off after about 5 minutes of use. The cooling fan also makes a grinding noise, suggesting a bearing issue.', 'Replaced the projector lamp module and cleaned the internal cooling fan and vents. Ran a 30-minute burn-in test with no flickering or shutdowns observed. Fan noise resolved after cleaning.', 'Juan Dela Cruz', '2026-06-20', 4500.00, 'COMPLETED', 1, 0, NULL, NULL, NULL, '2026-07-03 18:20:21'),
(2, 25, 'REPAIR', 'Asset flagged as repairable — requires maintenance', 'Pending review and assignment', NULL, '2026-07-05', 13000.00, 'SCHEDULED', 1, 0, NULL, NULL, NULL, '2026-07-05 22:40:33');

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
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`user_id`, `username`, `password_hash`, `full_name`, `role`, `office_id`, `is_active`, `failed_login_attempts`, `account_locked_until`, `created_at`) VALUES
(1, 'admin', '$2a$10$QLZqVUTL8zCKV0IByklVNuLTd4KZQfwtdxVth0FYUYoUx889rNRGO', 'Administrator', 'ADMIN', NULL, 1, 0, NULL, '2026-06-30 10:12:59'),
(2, 'ict_staff', '$2a$10$jzBKbPXcI3hdvUQPpHG.K.AQn/73lcYt8gJ9GZ/wFs4aytk1G/Bbu', 'ICT Officer', 'STAFF', NULL, 1, 0, NULL, '2026-06-30 10:12:59');

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
