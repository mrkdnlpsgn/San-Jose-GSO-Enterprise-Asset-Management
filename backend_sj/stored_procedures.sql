-- =============================================================
-- GSO Inventory Management System — Stored Procedures
-- Import AFTER running gso_inventory.sql
-- =============================================================

DELIMITER $$

-- =============================================================
-- AUTH
-- =============================================================

DROP PROCEDURE IF EXISTS sp_auth_get_user_for_login $$
CREATE PROCEDURE sp_auth_get_user_for_login(IN p_username VARCHAR(50))
BEGIN
    SELECT u.user_id AS id, u.username, u.password_hash AS password,
           u.full_name AS fullName, u.`role`, u.is_active AS isActive,
           u.failed_login_attempts AS failedLoginAttempts,
           u.account_locked_until AS accountLockedUntil,
           u.token_version AS tokenVersion,
           u.must_change_password AS mustChangePassword,
           u.privacy_acknowledged_at AS privacyAcknowledgedAt,
           u.two_factor_enabled AS twoFactorEnabled
    FROM users u
    WHERE LOWER(u.username) = LOWER(p_username);
END $$

DROP PROCEDURE IF EXISTS sp_auth_acknowledge_privacy $$
CREATE PROCEDURE sp_auth_acknowledge_privacy(IN p_id INT)
BEGIN
    UPDATE users SET privacy_acknowledged_at = NOW() WHERE user_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_auth_login_success $$
CREATE PROCEDURE sp_auth_login_success(IN p_user_id INT)
BEGIN
    UPDATE users SET failed_login_attempts = 0, account_locked_until = NULL
    WHERE user_id = p_user_id;
END $$

DROP PROCEDURE IF EXISTS sp_auth_login_failure $$
CREATE PROCEDURE sp_auth_login_failure(IN p_user_id INT, IN p_max_attempts INT, IN p_lockout_minutes INT)
BEGIN
    UPDATE users
    SET failed_login_attempts = failed_login_attempts + 1,
        account_locked_until = CASE
            WHEN failed_login_attempts + 1 >= p_max_attempts
                THEN DATE_ADD(NOW(), INTERVAL p_lockout_minutes MINUTE)
            ELSE account_locked_until
        END
    WHERE user_id = p_user_id;
END $$

-- Step 1 of forgot-password: look up the account + email to decide (in Java) whether
-- an OTP should be generated and emailed. Caller always returns the same generic HTTP
-- response regardless of what this returns, to avoid a username-existence oracle.
DROP PROCEDURE IF EXISTS sp_auth_get_user_for_forgot_password_request $$
CREATE PROCEDURE sp_auth_get_user_for_forgot_password_request(IN p_username VARCHAR(50))
BEGIN
    SELECT user_id AS id, username, email, is_active AS isActive,
           last_password_reset_at AS lastPasswordResetAt,
           password_reset_otp_expires_at AS otpExpiresAt
    FROM users
    WHERE LOWER(username) = LOWER(p_username);
END $$

DROP PROCEDURE IF EXISTS sp_auth_set_password_reset_otp $$
CREATE PROCEDURE sp_auth_set_password_reset_otp(
    IN p_user_id INT, IN p_otp_hash VARCHAR(255), IN p_expires_at DATETIME
)
BEGIN
    UPDATE users
    SET password_reset_otp_hash = p_otp_hash,
        password_reset_otp_expires_at = p_expires_at,
        password_reset_otp_attempts = 0
    WHERE user_id = p_user_id;
END $$

-- Step 2 of forgot-password: fetch the pending OTP (if any) to validate in Java.
DROP PROCEDURE IF EXISTS sp_auth_get_password_reset_otp $$
CREATE PROCEDURE sp_auth_get_password_reset_otp(IN p_username VARCHAR(50))
BEGIN
    SELECT user_id AS id, is_active AS isActive,
           password_reset_otp_hash AS otpHash,
           password_reset_otp_expires_at AS otpExpiresAt,
           password_reset_otp_attempts AS otpAttempts
    FROM users
    WHERE LOWER(username) = LOWER(p_username);
END $$

DROP PROCEDURE IF EXISTS sp_auth_increment_password_reset_otp_attempts $$
CREATE PROCEDURE sp_auth_increment_password_reset_otp_attempts(IN p_user_id INT)
BEGIN
    UPDATE users
    SET password_reset_otp_attempts = password_reset_otp_attempts + 1
    WHERE user_id = p_user_id;
END $$

DROP PROCEDURE IF EXISTS sp_auth_clear_password_reset_otp $$
CREATE PROCEDURE sp_auth_clear_password_reset_otp(IN p_user_id INT)
BEGIN
    UPDATE users
    SET password_reset_otp_hash = NULL,
        password_reset_otp_expires_at = NULL,
        password_reset_otp_attempts = 0
    WHERE user_id = p_user_id;
END $$

DROP PROCEDURE IF EXISTS sp_auth_forgot_password_reset $$
CREATE PROCEDURE sp_auth_forgot_password_reset(IN p_user_id INT, IN p_password_hash VARCHAR(255))
BEGIN
    UPDATE users
    SET password_hash = p_password_hash,
        last_password_reset_at = NOW(),
        failed_login_attempts = 0,
        account_locked_until = NULL,
        password_reset_otp_hash = NULL,
        password_reset_otp_expires_at = NULL,
        password_reset_otp_attempts = 0,
        token_version = token_version + 1
    WHERE user_id = p_user_id;
END $$

-- Step 2 of login 2FA: store a fresh code for an account that passed the
-- password check and has two_factor_enabled — mirrors sp_auth_set_password_reset_otp.
DROP PROCEDURE IF EXISTS sp_auth_set_login_otp $$
CREATE PROCEDURE sp_auth_set_login_otp(
    IN p_user_id INT, IN p_otp_hash VARCHAR(255), IN p_expires_at DATETIME
)
BEGIN
    UPDATE users
    SET login_otp_hash = p_otp_hash,
        login_otp_expires_at = p_expires_at,
        login_otp_attempts = 0
    WHERE user_id = p_user_id;
END $$

-- Step 3: fetch the pending login OTP plus everything needed to issue a session
-- (token_version, role, etc.) so a successful verify can finish login in one
-- more call without a second lookup.
DROP PROCEDURE IF EXISTS sp_auth_get_login_otp $$
CREATE PROCEDURE sp_auth_get_login_otp(IN p_username VARCHAR(50))
BEGIN
    SELECT user_id AS id, username, full_name AS fullName, `role`,
           is_active AS isActive, token_version AS tokenVersion,
           privacy_acknowledged_at AS privacyAcknowledgedAt,
           login_otp_hash AS otpHash,
           login_otp_expires_at AS otpExpiresAt,
           login_otp_attempts AS otpAttempts
    FROM users
    WHERE LOWER(username) = LOWER(p_username);
END $$

DROP PROCEDURE IF EXISTS sp_auth_increment_login_otp_attempts $$
CREATE PROCEDURE sp_auth_increment_login_otp_attempts(IN p_user_id INT)
BEGIN
    UPDATE users
    SET login_otp_attempts = login_otp_attempts + 1
    WHERE user_id = p_user_id;
END $$

-- Called once a login OTP has been consumed successfully — clears it so it
-- can't be replayed, without touching anything else (unlike the forgot-password
-- flow, nothing else needs to change here: no password/token_version bump).
DROP PROCEDURE IF EXISTS sp_auth_clear_login_otp $$
CREATE PROCEDURE sp_auth_clear_login_otp(IN p_user_id INT)
BEGIN
    UPDATE users
    SET login_otp_hash = NULL,
        login_otp_expires_at = NULL,
        login_otp_attempts = 0
    WHERE user_id = p_user_id;
END $$

-- =============================================================
-- OFFICES
-- =============================================================

DROP PROCEDURE IF EXISTS sp_offices_get_all $$
CREATE PROCEDURE sp_offices_get_all()
BEGIN
    SELECT o.office_id AS id, o.office_name AS officeName, o.created_at AS createdAt,
           u.user_id AS hu_id, u.username AS hu_username, u.full_name AS hu_fullName
    FROM offices o
    LEFT JOIN users u ON o.head_user_id = u.user_id
    ORDER BY o.office_name;
END $$

DROP PROCEDURE IF EXISTS sp_offices_search $$
CREATE PROCEDURE sp_offices_search(IN p_search VARCHAR(255))
BEGIN
    SET p_search = TRIM(p_search);
    SELECT o.office_id AS id, o.office_name AS officeName, o.created_at AS createdAt,
           u.user_id AS hu_id, u.username AS hu_username, u.full_name AS hu_fullName
    FROM offices o
    LEFT JOIN users u ON o.head_user_id = u.user_id
    WHERE o.office_name LIKE CONCAT('%', p_search, '%')
    ORDER BY o.office_name;
END $$

DROP PROCEDURE IF EXISTS sp_offices_get_by_id $$
CREATE PROCEDURE sp_offices_get_by_id(IN p_id INT)
BEGIN
    SELECT o.office_id AS id, o.office_name AS officeName, o.created_at AS createdAt,
           u.user_id AS hu_id, u.username AS hu_username, u.full_name AS hu_fullName
    FROM offices o
    LEFT JOIN users u ON o.head_user_id = u.user_id
    WHERE o.office_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_offices_create $$
CREATE PROCEDURE sp_offices_create(IN p_name VARCHAR(100), IN p_head_user_id INT, OUT p_id INT)
BEGIN
    INSERT INTO offices(office_name, head_user_id, created_at)
    VALUES(p_name, NULLIF(p_head_user_id, 0), NOW());
    SET p_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_offices_update $$
CREATE PROCEDURE sp_offices_update(IN p_id INT, IN p_name VARCHAR(100), IN p_head_user_id INT)
BEGIN
    UPDATE offices
    SET office_name = p_name, head_user_id = NULLIF(p_head_user_id, 0)
    WHERE office_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_offices_delete $$
CREATE PROCEDURE sp_offices_delete(IN p_id INT)
BEGIN
    DELETE FROM offices WHERE office_id = p_id;
END $$

-- =============================================================
-- CATEGORIES
-- =============================================================

DROP PROCEDURE IF EXISTS sp_categories_get_all $$
CREATE PROCEDURE sp_categories_get_all()
BEGIN
    SELECT category_id AS id, category_name AS categoryName, `description`
    FROM categories ORDER BY category_name;
END $$

DROP PROCEDURE IF EXISTS sp_categories_search $$
CREATE PROCEDURE sp_categories_search(IN p_search VARCHAR(255))
BEGIN
    SET p_search = TRIM(p_search);
    SELECT category_id AS id, category_name AS categoryName, `description`
    FROM categories
    WHERE category_name LIKE CONCAT('%', p_search, '%')
       OR `description` LIKE CONCAT('%', p_search, '%')
    ORDER BY category_name;
END $$

DROP PROCEDURE IF EXISTS sp_categories_get_by_id $$
CREATE PROCEDURE sp_categories_get_by_id(IN p_id INT)
BEGIN
    SELECT category_id AS id, category_name AS categoryName, `description`
    FROM categories WHERE category_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_categories_name_exists $$
CREATE PROCEDURE sp_categories_name_exists(IN p_name VARCHAR(100), OUT p_exists BOOLEAN)
BEGIN
    SELECT COUNT(*) > 0 INTO p_exists FROM categories
    WHERE LOWER(category_name) = LOWER(p_name);
END $$

DROP PROCEDURE IF EXISTS sp_categories_create $$
CREATE PROCEDURE sp_categories_create(IN p_name VARCHAR(100), IN p_description TEXT, OUT p_id INT)
BEGIN
    INSERT INTO categories(category_name, `description`) VALUES(p_name, p_description);
    SET p_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_categories_update $$
CREATE PROCEDURE sp_categories_update(IN p_id INT, IN p_name VARCHAR(100), IN p_description TEXT)
BEGIN
    UPDATE categories SET category_name = p_name, `description` = p_description
    WHERE category_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_categories_delete $$
CREATE PROCEDURE sp_categories_delete(IN p_id INT)
BEGIN
    DELETE FROM categories WHERE category_id = p_id;
END $$

-- =============================================================
-- USERS
-- =============================================================

DROP PROCEDURE IF EXISTS sp_users_get_all $$
CREATE PROCEDURE sp_users_get_all()
BEGIN
    SELECT u.user_id AS id, u.username, u.email, u.full_name AS fullName, u.`role`,
           u.is_active AS isActive, u.created_at AS createdAt,
           o.office_id AS office_id, o.office_name AS office_officeName
    FROM users u
    LEFT JOIN offices o ON u.office_id = o.office_id
    ORDER BY u.full_name;
END $$

DROP PROCEDURE IF EXISTS sp_users_search $$
CREATE PROCEDURE sp_users_search(IN p_search VARCHAR(255))
BEGIN
    SET p_search = TRIM(p_search);
    SELECT u.user_id AS id, u.username, u.email, u.full_name AS fullName, u.`role`,
           u.is_active AS isActive, u.created_at AS createdAt,
           o.office_id AS office_id, o.office_name AS office_officeName
    FROM users u
    LEFT JOIN offices o ON u.office_id = o.office_id
    WHERE u.username LIKE CONCAT('%', p_search, '%')
       OR u.full_name LIKE CONCAT('%', p_search, '%')
       OR u.`role` LIKE CONCAT('%', p_search, '%')
       OR o.office_name LIKE CONCAT('%', p_search, '%')
    ORDER BY u.full_name;
END $$

DROP PROCEDURE IF EXISTS sp_users_get_by_id $$
CREATE PROCEDURE sp_users_get_by_id(IN p_id INT)
BEGIN
    SELECT u.user_id AS id, u.username, u.email, u.full_name AS fullName, u.`role`,
           u.is_active AS isActive, u.created_at AS createdAt,
           o.office_id AS office_id, o.office_name AS office_officeName
    FROM users u
    LEFT JOIN offices o ON u.office_id = o.office_id
    WHERE u.user_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_users_get_by_username $$
CREATE PROCEDURE sp_users_get_by_username(IN p_username VARCHAR(50))
BEGIN
    SELECT u.user_id AS id, u.username, u.password_hash AS password,
           u.full_name AS fullName, u.`role`, u.is_active AS isActive,
           u.failed_login_attempts AS failedLoginAttempts,
           u.account_locked_until AS accountLockedUntil,
           u.created_at AS createdAt,
           o.office_id AS office_id, o.office_name AS office_officeName
    FROM users u
    LEFT JOIN offices o ON u.office_id = o.office_id
    WHERE LOWER(u.username) = LOWER(p_username);
END $$

DROP PROCEDURE IF EXISTS sp_users_username_exists $$
CREATE PROCEDURE sp_users_username_exists(IN p_username VARCHAR(50), OUT p_exists BOOLEAN)
BEGIN
    SELECT COUNT(*) > 0 INTO p_exists FROM users
    WHERE LOWER(username) = LOWER(p_username);
END $$

-- p_exclude_id lets an update check "does any OTHER user already have this email"
-- (pass 0 on create, since no row to exclude yet).
DROP PROCEDURE IF EXISTS sp_users_email_exists $$
CREATE PROCEDURE sp_users_email_exists(IN p_email VARCHAR(255), IN p_exclude_id INT, OUT p_exists BOOLEAN)
BEGIN
    SELECT COUNT(*) > 0 INTO p_exists FROM users
    WHERE LOWER(email) = LOWER(p_email) AND user_id != p_exclude_id;
END $$

DROP PROCEDURE IF EXISTS sp_users_create $$
CREATE PROCEDURE sp_users_create(
    IN p_username VARCHAR(50), IN p_email VARCHAR(255), IN p_password_hash VARCHAR(255),
    IN p_full_name VARCHAR(100), IN p_role VARCHAR(20),
    IN p_office_id INT, IN p_is_active BOOLEAN,
    OUT p_id INT
)
BEGIN
    -- token_version has no column default and is NOT NULL — must be set
    -- explicitly or every new-user INSERT fails outright. 0 is the same
    -- starting value JwtUtil/AuthService already assume for a user with no
    -- recorded version (see login()'s `tokenVersion() != null ? ... : 0`).
    INSERT INTO users(username, email, password_hash, full_name, `role`, office_id, is_active, token_version, created_at)
    VALUES(p_username, NULLIF(p_email, ''), p_password_hash, p_full_name, p_role, NULLIF(p_office_id, 0), p_is_active, 0, NOW());
    SET p_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_users_update $$
CREATE PROCEDURE sp_users_update(
    IN p_id INT, IN p_email VARCHAR(255), IN p_full_name VARCHAR(100), IN p_role VARCHAR(20),
    IN p_office_id INT, IN p_is_active BOOLEAN, IN p_password_hash VARCHAR(255)
)
BEGIN
    UPDATE users
    SET email = NULLIF(p_email, ''),
        full_name = p_full_name,
        `role` = p_role,
        office_id = NULLIF(p_office_id, 0),
        is_active = p_is_active,
        password_hash = IF(p_password_hash IS NULL OR p_password_hash = '', password_hash, p_password_hash)
    WHERE user_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_users_change_password $$
CREATE PROCEDURE sp_users_change_password(IN p_id INT, IN p_password_hash VARCHAR(255))
BEGIN
    UPDATE users
    SET password_hash = p_password_hash,
        token_version = token_version + 1
    WHERE user_id = p_id;
END $$

-- Self-service completion of a forced password change (first login after account
-- creation or an admin-mediated reset). Combines a normal password change with
-- clearing must_change_password and any lockout state left over from earlier attempts.
DROP PROCEDURE IF EXISTS sp_auth_complete_forced_password_change $$
CREATE PROCEDURE sp_auth_complete_forced_password_change(IN p_id INT, IN p_password_hash VARCHAR(255))
BEGIN
    UPDATE users
    SET password_hash = p_password_hash,
        token_version = token_version + 1,
        must_change_password = FALSE,
        failed_login_attempts = 0,
        account_locked_until = NULL
    WHERE user_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_users_delete $$
CREATE PROCEDURE sp_users_delete(IN p_id INT)
BEGIN
    DELETE FROM users WHERE user_id = p_id;
END $$

-- =============================================================
-- ASSETS
-- =============================================================

DROP PROCEDURE IF EXISTS sp_assets_get_all $$
DROP PROCEDURE IF EXISTS sp_assets_search $$
DROP PROCEDURE IF EXISTS sp_assets_list $$
CREATE PROCEDURE sp_assets_list(
    IN p_search VARCHAR(255), IN p_limit INT, IN p_offset INT,
    IN p_category_id INT, IN p_office_id INT,
    IN p_condition VARCHAR(20), IN p_lifecycle_status VARCHAR(30)
)
BEGIN
    SET p_search = TRIM(p_search);
    SELECT a.asset_id AS id, a.property_number AS propertyNumber, a.serial_number AS serialNumber, a.`description`,
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
        OR a.serial_number    LIKE CONCAT('%', p_search, '%')
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
END $$

-- Mirrors sp_assets_list's filters minus LIMIT/OFFSET — backs a lightweight
-- /count endpoint so the mobile app can show a true total without fetching
-- every row (list screens paginate 20 at a time and never see a real total).
DROP PROCEDURE IF EXISTS sp_assets_count $$
CREATE PROCEDURE sp_assets_count(
    IN p_search VARCHAR(255),
    IN p_category_id INT, IN p_office_id INT,
    IN p_condition VARCHAR(20), IN p_lifecycle_status VARCHAR(30)
)
BEGIN
    SET p_search = TRIM(p_search);
    SELECT COUNT(*) AS total
    FROM assets a
    LEFT JOIN categories c ON a.category_id = c.category_id
    LEFT JOIN offices o ON a.office_id = o.office_id
    WHERE a.is_deleted = FALSE
      AND (
        p_search IS NULL OR p_search = '' OR
        a.property_number    LIKE CONCAT('%', p_search, '%')
        OR a.serial_number    LIKE CONCAT('%', p_search, '%')
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
      AND (p_lifecycle_status IS NULL OR p_lifecycle_status = '' OR a.lifecycle_status = p_lifecycle_status);
END $$

DROP PROCEDURE IF EXISTS sp_assets_get_by_id $$
CREATE PROCEDURE sp_assets_get_by_id(IN p_id INT)
BEGIN
    SELECT a.asset_id AS id, a.property_number AS propertyNumber, a.serial_number AS serialNumber, a.`description`,
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
END $$

DROP PROCEDURE IF EXISTS sp_assets_create $$
CREATE PROCEDURE sp_assets_create(
    IN p_property_number VARCHAR(50), IN p_serial_number VARCHAR(100), IN p_description VARCHAR(255),
    IN p_category_id INT, IN p_quantity INT, IN p_acquisition_date DATE,
    IN p_unit_value DECIMAL(12,2), IN p_office_id INT,
    IN p_accountable_person VARCHAR(150), IN p_physical_count INT, IN p_location VARCHAR(150),
    IN p_condition VARCHAR(20), IN p_lifecycle_status VARCHAR(30),
    IN p_qr_code_path VARCHAR(255), IN p_sha256_hash VARCHAR(64), IN p_remarks TEXT,
    OUT p_id INT
)
BEGIN
    INSERT INTO assets(
        property_number, serial_number, `description`, category_id, quantity, acquisition_date,
        unit_value, office_id, accountable_person, physical_count, location, `condition`,
        lifecycle_status, qr_code_path, sha256_hash, remarks,
        is_deleted, created_at, updated_at
    ) VALUES (
        p_property_number, NULLIF(p_serial_number, ''), p_description, p_category_id, p_quantity, p_acquisition_date,
        p_unit_value, p_office_id, p_accountable_person, p_physical_count, p_location, p_condition,
        p_lifecycle_status, NULLIF(p_qr_code_path, ''), NULLIF(p_sha256_hash, ''), NULLIF(p_remarks, ''),
        FALSE, NOW(), NOW()
    );
    SET p_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_assets_update $$
CREATE PROCEDURE sp_assets_update(
    IN p_id INT, IN p_property_number VARCHAR(50), IN p_serial_number VARCHAR(100), IN p_description VARCHAR(255),
    IN p_category_id INT, IN p_quantity INT, IN p_acquisition_date DATE,
    IN p_unit_value DECIMAL(12,2), IN p_office_id INT,
    IN p_accountable_person VARCHAR(150), IN p_physical_count INT, IN p_location VARCHAR(150),
    IN p_condition VARCHAR(20), IN p_lifecycle_status VARCHAR(30),
    IN p_qr_code_path VARCHAR(255), IN p_sha256_hash VARCHAR(64), IN p_remarks TEXT
)
BEGIN
    UPDATE assets SET
        property_number = p_property_number, serial_number = NULLIF(p_serial_number, ''), `description` = p_description,
        category_id = p_category_id, quantity = p_quantity,
        acquisition_date = p_acquisition_date, unit_value = p_unit_value,
        office_id = p_office_id, accountable_person = p_accountable_person,
        physical_count = p_physical_count,
        location = p_location, `condition` = p_condition,
        lifecycle_status = p_lifecycle_status,
        qr_code_path = NULLIF(p_qr_code_path, ''), sha256_hash = NULLIF(p_sha256_hash, ''),
        remarks = NULLIF(p_remarks, ''), updated_at = NOW()
    WHERE asset_id = p_id AND is_deleted = FALSE;
END $$

DROP PROCEDURE IF EXISTS sp_assets_update_lifecycle $$
CREATE PROCEDURE sp_assets_update_lifecycle(IN p_id INT, IN p_lifecycle_status VARCHAR(30))
BEGIN
    UPDATE assets SET lifecycle_status = p_lifecycle_status, updated_at = NOW()
    WHERE asset_id = p_id AND is_deleted = FALSE;
END $$

DROP PROCEDURE IF EXISTS sp_assets_soft_delete $$
CREATE PROCEDURE sp_assets_soft_delete(
    IN p_id INT, IN p_deleted_by INT, IN p_deleted_by_username VARCHAR(50), IN p_reason TEXT
)
BEGIN
    INSERT INTO deleted_assets(
        asset_id, property_number, `description`, category_id, category_name,
        quantity, acquisition_date, unit_value, office_id, office_name,
        accountable_person_name, location, `condition`, asset_condition, lifecycle_status,
        qr_code_path, sha256_hash, remarks,
        original_created_at, original_updated_at,
        deleted_by_user_id, deleted_by_username, delete_reason, deleted_at,
        asset_condition
    )
    SELECT a.asset_id, a.property_number, a.`description`, a.category_id, c.category_name,
           a.quantity, a.acquisition_date, a.unit_value, a.office_id, o.office_name,
           a.accountable_person, a.location, a.`condition`, a.`condition`, a.lifecycle_status,
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
END $$

-- The original assets row is only ever soft-deleted in place (never removed),
-- so restoring is just un-flagging it and dropping its archive snapshot —
-- no data has to be reconstructed. Also cascades to any maintenance/disposal
-- record that was archived alongside this same asset (see
-- sp_maintenance_soft_delete_by_asset / sp_disposal_soft_delete_by_asset) —
-- otherwise restoring the asset leaves its ledger record stuck looking
-- deleted, or restoring the ledger record leaves its asset stuck deleted.
DROP PROCEDURE IF EXISTS sp_assets_restore $$
CREATE PROCEDURE sp_assets_restore(IN p_deleted_asset_id INT)
BEGIN
    DECLARE v_asset_id INT;
    SELECT asset_id INTO v_asset_id FROM deleted_assets WHERE deleted_asset_id = p_deleted_asset_id;

    UPDATE assets a
    JOIN deleted_assets da ON da.asset_id = a.asset_id
    SET a.is_deleted = FALSE, a.deleted_at = NULL, a.deleted_by = NULL, a.delete_reason = NULL
    WHERE da.deleted_asset_id = p_deleted_asset_id;

    DELETE FROM deleted_assets WHERE deleted_asset_id = p_deleted_asset_id;

    UPDATE maintenance_ledger m
    JOIN deleted_maintenance dm ON dm.maintenance_id = m.maintenance_id
    SET m.is_deleted = FALSE, m.deleted_at = NULL, m.deleted_by = NULL, m.delete_reason = NULL
    WHERE dm.asset_id = v_asset_id;
    DELETE FROM deleted_maintenance WHERE asset_id = v_asset_id;

    UPDATE disposal_ledger d
    JOIN deleted_disposal dd ON dd.disposal_id = d.disposal_id
    SET d.is_deleted = FALSE, d.deleted_at = NULL, d.deleted_by = NULL, d.delete_reason = NULL
    WHERE dd.asset_id = v_asset_id;
    DELETE FROM deleted_disposal WHERE asset_id = v_asset_id;
END $$

-- =============================================================
-- ASSET HISTORY
-- =============================================================

DROP PROCEDURE IF EXISTS sp_asset_history_get_all $$
CREATE PROCEDURE sp_asset_history_get_all()
BEGIN
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
END $$

DROP PROCEDURE IF EXISTS sp_asset_history_search $$
CREATE PROCEDURE sp_asset_history_search(IN p_search VARCHAR(255))
BEGIN
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
END $$

DROP PROCEDURE IF EXISTS sp_asset_history_get_by_asset $$
CREATE PROCEDURE sp_asset_history_get_by_asset(IN p_asset_id INT)
BEGIN
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
END $$

DROP PROCEDURE IF EXISTS sp_asset_history_create $$
CREATE PROCEDURE sp_asset_history_create(
    IN p_asset_id INT, IN p_event_type VARCHAR(30),
    IN p_from_office_id INT, IN p_to_office_id INT,
    IN p_performed_by INT, IN p_notes TEXT,
    OUT p_id INT
)
BEGIN
    INSERT INTO asset_history(asset_id, event_type, from_office_id, to_office_id, performed_by, event_date, notes)
    VALUES(p_asset_id, p_event_type, NULLIF(p_from_office_id, 0), NULLIF(p_to_office_id, 0),
           p_performed_by, NOW(), NULLIF(p_notes, ''));
    SET p_id = LAST_INSERT_ID();
END $$

-- =============================================================
-- MAINTENANCE LEDGER
-- =============================================================

DROP PROCEDURE IF EXISTS sp_maintenance_get_all $$
DROP PROCEDURE IF EXISTS sp_maintenance_search $$
DROP PROCEDURE IF EXISTS sp_maintenance_list $$
CREATE PROCEDURE sp_maintenance_list(
    IN p_search VARCHAR(255), IN p_limit INT, IN p_offset INT,
    IN p_maintenance_type VARCHAR(20), IN p_status VARCHAR(20)
)
BEGIN
    SET p_search = TRIM(p_search);
    SELECT m.maintenance_id AS id, m.maintenance_type AS maintenanceType,
           m.findings, m.actions_taken AS actionsTaken,
           m.maintenance_date AS maintenanceDate, m.cost, m.`status`, m.created_at AS createdAt, m.updated_at AS updatedAt,
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
END $$

-- Mirrors sp_maintenance_list's filters minus LIMIT/OFFSET — see sp_assets_count.
DROP PROCEDURE IF EXISTS sp_maintenance_count $$
CREATE PROCEDURE sp_maintenance_count(
    IN p_search VARCHAR(255),
    IN p_maintenance_type VARCHAR(20), IN p_status VARCHAR(20)
)
BEGIN
    SET p_search = TRIM(p_search);
    SELECT COUNT(*) AS total
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
      AND (p_status IS NULL OR p_status = '' OR m.`status` = p_status);
END $$

DROP PROCEDURE IF EXISTS sp_maintenance_get_by_id $$
CREATE PROCEDURE sp_maintenance_get_by_id(IN p_id INT)
BEGIN
    SELECT m.maintenance_id AS id, m.maintenance_type AS maintenanceType,
           m.findings, m.actions_taken AS actionsTaken,
           m.maintenance_date AS maintenanceDate, m.cost, m.`status`, m.created_at AS createdAt, m.updated_at AS updatedAt,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           r.user_id AS rb_id, r.username AS rb_username, r.full_name AS rb_fullName,
           m.assigned_to AS assignedTo
    FROM maintenance_ledger m
    LEFT JOIN assets a ON m.asset_id = a.asset_id
    LEFT JOIN users r ON m.recorded_by = r.user_id
    WHERE m.maintenance_id = p_id AND m.is_deleted = FALSE;
END $$

DROP PROCEDURE IF EXISTS sp_maintenance_get_by_asset $$
CREATE PROCEDURE sp_maintenance_get_by_asset(IN p_asset_id INT)
BEGIN
    SELECT m.maintenance_id AS id, m.maintenance_type AS maintenanceType,
           m.findings, m.actions_taken AS actionsTaken,
           m.maintenance_date AS maintenanceDate, m.cost, m.`status`, m.created_at AS createdAt, m.updated_at AS updatedAt,
           a.asset_id, a.property_number AS asset_propertyNumber, a.`description` AS asset_description,
           r.user_id AS rb_id, r.username AS rb_username, r.full_name AS rb_fullName,
           m.assigned_to AS assignedTo
    FROM maintenance_ledger m
    LEFT JOIN assets a ON m.asset_id = a.asset_id
    LEFT JOIN users r ON m.recorded_by = r.user_id
    WHERE m.asset_id = p_asset_id AND m.is_deleted = FALSE
    ORDER BY m.maintenance_date DESC;
END $$

DROP PROCEDURE IF EXISTS sp_maintenance_create $$
CREATE PROCEDURE sp_maintenance_create(
    IN p_asset_id INT, IN p_maintenance_type VARCHAR(20),
    IN p_findings TEXT, IN p_actions_taken TEXT,
    IN p_assigned_to VARCHAR(150), IN p_maintenance_date DATE,
    IN p_cost DECIMAL(10,2), IN p_status VARCHAR(20), IN p_recorded_by INT,
    OUT p_id INT
)
BEGIN
    INSERT INTO maintenance_ledger(
        asset_id, maintenance_type, findings, actions_taken, assigned_to,
        maintenance_date, cost, `status`, recorded_by, is_deleted, created_at
    ) VALUES(
        p_asset_id, p_maintenance_type, p_findings, p_actions_taken, NULLIF(p_assigned_to, ''),
        p_maintenance_date, p_cost, p_status, NULLIF(p_recorded_by, 0), FALSE, NOW()
    );
    SET p_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_maintenance_update $$
CREATE PROCEDURE sp_maintenance_update(
    IN p_id INT, IN p_maintenance_type VARCHAR(20),
    IN p_findings TEXT, IN p_actions_taken TEXT,
    IN p_assigned_to VARCHAR(150), IN p_maintenance_date DATE,
    IN p_cost DECIMAL(10,2), IN p_status VARCHAR(20)
)
BEGIN
    UPDATE maintenance_ledger SET
        maintenance_type = p_maintenance_type, findings = p_findings,
        actions_taken = p_actions_taken, assigned_to = NULLIF(p_assigned_to, ''),
        maintenance_date = p_maintenance_date, cost = p_cost, `status` = p_status
    WHERE maintenance_id = p_id AND is_deleted = FALSE;
END $$

DROP PROCEDURE IF EXISTS sp_maintenance_soft_delete $$
CREATE PROCEDURE sp_maintenance_soft_delete(
    IN p_id INT, IN p_deleted_by INT, IN p_deleted_by_username VARCHAR(50), IN p_reason TEXT
)
BEGIN
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
END $$

-- Also cascades back to the parent asset if it's currently deleted too (see
-- sp_assets_restore's comment for why this needs to go both directions).
DROP PROCEDURE IF EXISTS sp_maintenance_restore $$
CREATE PROCEDURE sp_maintenance_restore(IN p_deleted_maintenance_id INT)
BEGIN
    DECLARE v_asset_id INT;
    SELECT asset_id INTO v_asset_id FROM deleted_maintenance WHERE deleted_maintenance_id = p_deleted_maintenance_id;

    UPDATE maintenance_ledger m
    JOIN deleted_maintenance dm ON dm.maintenance_id = m.maintenance_id
    SET m.is_deleted = FALSE, m.deleted_at = NULL, m.deleted_by = NULL, m.delete_reason = NULL
    WHERE dm.deleted_maintenance_id = p_deleted_maintenance_id;

    DELETE FROM deleted_maintenance WHERE deleted_maintenance_id = p_deleted_maintenance_id;

    UPDATE assets a
    JOIN deleted_assets da ON da.asset_id = a.asset_id
    SET a.is_deleted = FALSE, a.deleted_at = NULL, a.deleted_by = NULL, a.delete_reason = NULL
    WHERE da.asset_id = v_asset_id;
    DELETE FROM deleted_assets WHERE asset_id = v_asset_id;
END $$

DROP PROCEDURE IF EXISTS sp_maintenance_delete_by_asset $$
CREATE PROCEDURE sp_maintenance_delete_by_asset(IN p_asset_id INT)
BEGIN
    UPDATE maintenance_ledger
    SET is_deleted = TRUE, deleted_at = NOW()
    WHERE asset_id = p_asset_id AND is_deleted = FALSE;
END $$

-- Used when the parent asset itself is deleted (as opposed to a condition
-- change cascading via sp_maintenance_delete_by_asset above, which doesn't
-- archive) — an asset's active maintenance record should show up in its own
-- Recycle Bin section too, not just under the asset's.
DROP PROCEDURE IF EXISTS sp_maintenance_soft_delete_by_asset $$
CREATE PROCEDURE sp_maintenance_soft_delete_by_asset(
    IN p_asset_id INT, IN p_deleted_by INT, IN p_deleted_by_username VARCHAR(50), IN p_reason TEXT
)
BEGIN
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
    WHERE m.asset_id = p_asset_id AND m.is_deleted = FALSE;

    UPDATE maintenance_ledger
    SET is_deleted = TRUE, deleted_at = NOW(), deleted_by = p_deleted_by, delete_reason = p_reason
    WHERE asset_id = p_asset_id AND is_deleted = FALSE;
END $$

-- =============================================================
-- DISPOSAL LEDGER
-- =============================================================

DROP PROCEDURE IF EXISTS sp_disposal_get_all $$
DROP PROCEDURE IF EXISTS sp_disposal_search $$
DROP PROCEDURE IF EXISTS sp_disposal_list $$
CREATE PROCEDURE sp_disposal_list(
    IN p_search VARCHAR(255), IN p_limit INT, IN p_offset INT,
    IN p_recommended_method VARCHAR(20), IN p_disposal_status VARCHAR(20)
)
BEGIN
    SET p_search = TRIM(p_search);
    SELECT d.disposal_id AS id, d.reason, d.inspection_findings AS inspectionFindings,
           d.recommended_method AS recommendedMethod, d.disposal_status AS disposalStatus,
           d.inspection_date AS inspectionDate, d.created_at AS createdAt, d.updated_at AS updatedAt,
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
END $$

-- Mirrors sp_disposal_list's filters minus LIMIT/OFFSET — see sp_assets_count.
DROP PROCEDURE IF EXISTS sp_disposal_count $$
CREATE PROCEDURE sp_disposal_count(
    IN p_search VARCHAR(255),
    IN p_recommended_method VARCHAR(20), IN p_disposal_status VARCHAR(20)
)
BEGIN
    SET p_search = TRIM(p_search);
    SELECT COUNT(*) AS total
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
      AND (p_disposal_status IS NULL OR p_disposal_status = '' OR d.disposal_status = p_disposal_status);
END $$

DROP PROCEDURE IF EXISTS sp_disposal_get_by_id $$
CREATE PROCEDURE sp_disposal_get_by_id(IN p_id INT)
BEGIN
    SELECT d.disposal_id AS id, d.reason, d.inspection_findings AS inspectionFindings,
           d.recommended_method AS recommendedMethod, d.disposal_status AS disposalStatus,
           d.inspection_date AS inspectionDate, d.created_at AS createdAt, d.updated_at AS updatedAt,
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
END $$

DROP PROCEDURE IF EXISTS sp_disposal_get_by_asset $$
CREATE PROCEDURE sp_disposal_get_by_asset(IN p_asset_id INT)
BEGIN
    SELECT d.disposal_id AS id, d.reason, d.inspection_findings AS inspectionFindings,
           d.recommended_method AS recommendedMethod, d.disposal_status AS disposalStatus,
           d.inspection_date AS inspectionDate, d.created_at AS createdAt, d.updated_at AS updatedAt,
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
END $$

DROP PROCEDURE IF EXISTS sp_disposal_create $$
CREATE PROCEDURE sp_disposal_create(
    IN p_asset_id INT, IN p_reason TEXT, IN p_inspection_findings TEXT,
    IN p_recommended_method VARCHAR(20), IN p_disposal_status VARCHAR(20),
    IN p_inspection_date DATE, IN p_approved_by VARCHAR(150), IN p_recorded_by INT,
    IN p_appraised_value DECIMAL(12,2), IN p_or_number VARCHAR(50), IN p_amount DECIMAL(12,2),
    OUT p_id INT
)
BEGIN
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
END $$

DROP PROCEDURE IF EXISTS sp_disposal_update $$
CREATE PROCEDURE sp_disposal_update(
    IN p_id INT, IN p_reason TEXT, IN p_inspection_findings TEXT,
    IN p_recommended_method VARCHAR(20), IN p_disposal_status VARCHAR(20),
    IN p_inspection_date DATE, IN p_approved_by VARCHAR(150),
    IN p_appraised_value DECIMAL(12,2), IN p_or_number VARCHAR(50), IN p_amount DECIMAL(12,2)
)
BEGIN
    UPDATE disposal_ledger SET
        reason = p_reason, inspection_findings = p_inspection_findings,
        recommended_method = p_recommended_method, disposal_status = p_disposal_status,
        inspection_date = p_inspection_date, approved_by = NULLIF(p_approved_by, ''),
        appraised_value = p_appraised_value, or_number = NULLIF(p_or_number, ''), amount = p_amount
    WHERE disposal_id = p_id AND is_deleted = FALSE;
END $$

DROP PROCEDURE IF EXISTS sp_disposal_soft_delete $$
CREATE PROCEDURE sp_disposal_soft_delete(
    IN p_id INT, IN p_deleted_by INT, IN p_deleted_by_username VARCHAR(50), IN p_reason TEXT
)
BEGIN
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
END $$

-- Also cascades back to the parent asset if it's currently deleted too (see
-- sp_assets_restore's comment for why this needs to go both directions).
DROP PROCEDURE IF EXISTS sp_disposal_restore $$
CREATE PROCEDURE sp_disposal_restore(IN p_deleted_disposal_id INT)
BEGIN
    DECLARE v_asset_id INT;
    SELECT asset_id INTO v_asset_id FROM deleted_disposal WHERE deleted_disposal_id = p_deleted_disposal_id;

    UPDATE disposal_ledger d
    JOIN deleted_disposal dd ON dd.disposal_id = d.disposal_id
    SET d.is_deleted = FALSE, d.deleted_at = NULL, d.deleted_by = NULL, d.delete_reason = NULL
    WHERE dd.deleted_disposal_id = p_deleted_disposal_id;

    DELETE FROM deleted_disposal WHERE deleted_disposal_id = p_deleted_disposal_id;

    UPDATE assets a
    JOIN deleted_assets da ON da.asset_id = a.asset_id
    SET a.is_deleted = FALSE, a.deleted_at = NULL, a.deleted_by = NULL, a.delete_reason = NULL
    WHERE da.asset_id = v_asset_id;
    DELETE FROM deleted_assets WHERE asset_id = v_asset_id;
END $$

DROP PROCEDURE IF EXISTS sp_disposal_delete_by_asset $$
CREATE PROCEDURE sp_disposal_delete_by_asset(IN p_asset_id INT)
BEGIN
    UPDATE disposal_ledger
    SET is_deleted = TRUE, deleted_at = NOW()
    WHERE asset_id = p_asset_id AND is_deleted = FALSE;
END $$

-- Same reasoning as sp_maintenance_soft_delete_by_asset above, for disposal.
DROP PROCEDURE IF EXISTS sp_disposal_soft_delete_by_asset $$
CREATE PROCEDURE sp_disposal_soft_delete_by_asset(
    IN p_asset_id INT, IN p_deleted_by INT, IN p_deleted_by_username VARCHAR(50), IN p_reason TEXT
)
BEGIN
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
    WHERE d.asset_id = p_asset_id AND d.is_deleted = FALSE;

    UPDATE disposal_ledger
    SET is_deleted = TRUE, deleted_at = NOW(), deleted_by = p_deleted_by, delete_reason = p_reason
    WHERE asset_id = p_asset_id AND is_deleted = FALSE;
END $$

-- =============================================================
-- AUDIT LOGS
-- =============================================================

DROP PROCEDURE IF EXISTS sp_audit_logs_get_all $$
CREATE PROCEDURE sp_audit_logs_get_all()
BEGIN
    SELECT l.log_id AS id, l.action, l.module, l.target_id AS targetId,
           l.target_type AS targetType, l.details, l.ip_address AS ipAddress,
           l.logged_at AS loggedAt,
           u.user_id AS u_id, u.username AS u_username, u.full_name AS u_fullName
    FROM audit_logs l
    LEFT JOIN users u ON l.user_id = u.user_id
    ORDER BY l.logged_at DESC;
END $$

DROP PROCEDURE IF EXISTS sp_audit_logs_search $$
CREATE PROCEDURE sp_audit_logs_search(IN p_search VARCHAR(255))
BEGIN
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
END $$

DROP PROCEDURE IF EXISTS sp_audit_logs_create $$
CREATE PROCEDURE sp_audit_logs_create(
    IN p_user_id INT, IN p_action VARCHAR(100), IN p_module VARCHAR(50),
    IN p_target_id INT, IN p_target_type VARCHAR(50),
    IN p_details TEXT, IN p_ip_address VARCHAR(45),
    OUT p_id INT
)
BEGIN
    INSERT INTO audit_logs(user_id, action, module, target_id, target_type, details, ip_address, logged_at)
    VALUES(p_user_id, p_action, p_module, NULLIF(p_target_id, 0), NULLIF(p_target_type, ''),
           NULLIF(p_details, ''), NULLIF(p_ip_address, ''), NOW());
    SET p_id = LAST_INSERT_ID();
END $$

DELIMITER ;

-- =============================================================
-- EQUIPMENT RECORDS
-- =============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_equipment_get_all $$
DROP PROCEDURE IF EXISTS sp_equipment_list $$
CREATE PROCEDURE sp_equipment_list(IN p_search VARCHAR(255), IN p_limit INT, IN p_offset INT)
BEGIN
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
END $$

DROP PROCEDURE IF EXISTS sp_equipment_get_by_id $$
CREATE PROCEDURE sp_equipment_get_by_id(IN p_id INT)
BEGIN
    SELECT equipment_id AS id, type, equipment_type AS equipmentType,
           item_code AS itemCode, article, office, location, description,
           accountable_person AS accountablePerson,
           accountable_person_phone AS accountablePersonPhone,
           accountable_person_email AS accountablePersonEmail,
           device_count AS deviceCount,
           created_at AS createdAt, updated_at AS updatedAt
    FROM equipment_records
    WHERE equipment_id = p_id;
END $$

DROP PROCEDURE IF EXISTS sp_equipment_create $$
CREATE PROCEDURE sp_equipment_create(
    IN  p_type                     VARCHAR(50),
    IN  p_equipment_type           VARCHAR(100),
    IN  p_item_code                VARCHAR(50),
    IN  p_article                  VARCHAR(255),
    IN  p_office                   VARCHAR(255),
    IN  p_location                 VARCHAR(255),
    IN  p_description              TEXT,
    IN  p_accountable_person       VARCHAR(150),
    IN  p_accountable_person_phone VARCHAR(50),
    IN  p_accountable_person_email VARCHAR(150),
    IN  p_device_count             INT,
    OUT p_new_id                   BIGINT
)
BEGIN
    INSERT INTO equipment_records (
        type, equipment_type, item_code, article, office, location, description,
        accountable_person, accountable_person_phone, accountable_person_email, device_count
    ) VALUES (
        p_type, p_equipment_type, p_item_code, p_article, p_office, p_location, p_description,
        p_accountable_person, p_accountable_person_phone, p_accountable_person_email,
        COALESCE(p_device_count, 0)
    );
    SET p_new_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_equipment_update $$
CREATE PROCEDURE sp_equipment_update(
    IN p_id                        INT,
    IN p_type                      VARCHAR(50),
    IN p_equipment_type            VARCHAR(100),
    IN p_item_code                 VARCHAR(50),
    IN p_article                   VARCHAR(255),
    IN p_office                    VARCHAR(255),
    IN p_location                  VARCHAR(255),
    IN p_description               TEXT,
    IN p_accountable_person        VARCHAR(150),
    IN p_accountable_person_phone  VARCHAR(50),
    IN p_accountable_person_email  VARCHAR(150),
    IN p_device_count              INT
)
BEGIN
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
END $$

DROP PROCEDURE IF EXISTS sp_equipment_delete $$
CREATE PROCEDURE sp_equipment_delete(IN p_id INT)
BEGIN
    DELETE FROM equipment_records WHERE equipment_id = p_id;
END $$

-- =============================================================
-- DEVICE RECORDS
-- =============================================================

DROP PROCEDURE IF EXISTS sp_devices_get_by_equipment $$
CREATE PROCEDURE sp_devices_get_by_equipment(IN p_equipment_id INT)
BEGIN
    SELECT device_id AS id, equipment_id AS equipmentId,
           item_code AS itemCode, serial_number AS serialNumber,
           model, amount_value AS amountValue, acquisition_date AS acquisitionDate,
           created_at AS createdAt, updated_at AS updatedAt
    FROM device_records
    WHERE equipment_id = p_equipment_id
    ORDER BY device_id ASC;
END $$

DROP PROCEDURE IF EXISTS sp_device_add $$
CREATE PROCEDURE sp_device_add(
    IN  p_equipment_id     INT,
    IN  p_item_code        VARCHAR(50),
    IN  p_serial_number    VARCHAR(100),
    IN  p_model            VARCHAR(100),
    IN  p_amount_value     DECIMAL(12,2),
    IN  p_acquisition_date DATE,
    OUT p_new_id           BIGINT
)
BEGIN
    INSERT INTO device_records (equipment_id, item_code, serial_number, model, amount_value, acquisition_date)
    VALUES (p_equipment_id, p_item_code, p_serial_number, p_model, p_amount_value, p_acquisition_date);
    SET p_new_id = LAST_INSERT_ID();
END $$

DROP PROCEDURE IF EXISTS sp_device_update $$
CREATE PROCEDURE sp_device_update(
    IN p_device_id         INT,
    IN p_item_code         VARCHAR(50),
    IN p_serial_number     VARCHAR(100),
    IN p_model             VARCHAR(100),
    IN p_amount_value      DECIMAL(12,2),
    IN p_acquisition_date  DATE
)
BEGIN
    UPDATE device_records
    SET item_code        = p_item_code,
        serial_number    = p_serial_number,
        model            = p_model,
        amount_value     = p_amount_value,
        acquisition_date = p_acquisition_date
    WHERE device_id = p_device_id;
END $$

DROP PROCEDURE IF EXISTS sp_device_delete $$
CREATE PROCEDURE sp_device_delete(IN p_device_id INT)
BEGIN
    DELETE FROM device_records WHERE device_id = p_device_id;
END $$

DELIMITER ;

-- =============================================================
-- END OF STORED PROCEDURES
-- =============================================================
