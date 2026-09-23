package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.AssetHistoryRequest;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.entity.Personnel;
import com.sanjose.inventory.entity.AssetHistory;
import com.sanjose.inventory.entity.Office;
import com.sanjose.inventory.entity.User;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class AssetHistoryService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;

    private static final RowMapper<AssetHistory> HISTORY_MAPPER = (rs, rn) -> {
        AssetHistory h = new AssetHistory();
        h.setId(rs.getLong("id"));
        String evType = rs.getString("eventType");
        h.setEventType(evType != null ? AssetHistory.EventType.valueOf(evType) : null);
        Timestamp evDate = rs.getTimestamp("eventDate");
        h.setEventDate(evDate != null ? evDate.toLocalDateTime() : null);
        h.setNotes(rs.getString("notes"));

        Long assetId = rs.getObject("asset_id", Long.class);
        if (assetId != null) {
            Asset a = new Asset();
            a.setId(assetId);
            a.setPropertyNumber(rs.getString("asset_propertyNumber"));
            a.setParNumber(rs.getString("asset_parNumber"));
            a.setGroupId(rs.getString("asset_groupId"));
            a.setSerialNumber(rs.getString("asset_serialNumber"));
            Long apId = rs.getObject("asset_personnelId", Long.class);
            if (apId != null) {
                Personnel ap = new Personnel();
                ap.setId(apId);
                ap.setFullName(rs.getString("asset_accountableName"));
                a.setAccountablePerson(ap);
            }
            Long acuId = rs.getObject("asset_currentUserId", Long.class);
            if (acuId != null) {
                Personnel acu = new Personnel();
                acu.setId(acuId);
                acu.setFullName(rs.getString("asset_currentUserName"));
                a.setCurrentUser(acu);
            }
            a.setDescription(rs.getString("asset_description"));
            h.setAsset(a);
        }

        Long pbId = rs.getObject("pb_id", Long.class);
        if (pbId != null) {
            User u = new User();
            u.setId(pbId);
            u.setUsername(rs.getString("pb_username"));
            u.setFullName(rs.getString("pb_fullName"));
            h.setPerformedBy(u);
        }

        Long foId = rs.getObject("fo_id", Long.class);
        if (foId != null) {
            Office fo = new Office();
            fo.setId(foId);
            fo.setOfficeName(rs.getString("fo_officeName"));
            h.setFromOffice(fo);
        }

        Long tooId = rs.getObject("too_id", Long.class);
        if (tooId != null) {
            Office too = new Office();
            too.setId(tooId);
            too.setOfficeName(rs.getString("too_officeName"));
            h.setToOffice(too);
        }

        return h;
    };

    public List<AssetHistory> findAll(String search, Long officeId) {
        if (search != null && !search.isBlank()) {
            return jdbcTemplate.query("CALL sp_asset_history_search(?, ?)", HISTORY_MAPPER, search.trim(), officeId);
        }
        return jdbcTemplate.query("CALL sp_asset_history_get_all(?)", HISTORY_MAPPER, officeId);
    }

    public List<AssetHistory> findByAsset(Long assetId) {
        return jdbcTemplate.query("CALL sp_asset_history_get_by_asset(?)", HISTORY_MAPPER, assetId);
    }

    /**
     * Fire-and-forget history entry for other services to call when a REGISTERED, TRANSFERRED,
     * MAINTENANCE, or DISPOSAL event actually happens — as opposed to {@link #create}, which
     * serves the manual "Log Asset Event" endpoint and returns the fully-joined record for the API response.
     */
    public void logEvent(Long assetId, String eventType, Long fromOfficeId, Long toOfficeId, Long performedById, String notes) {
        SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_asset_history_create(?, ?, ?, ?, ?, ?, ?)",
            assetId,
            eventType,
            fromOfficeId != null ? fromOfficeId.intValue() : 0,
            toOfficeId != null ? toOfficeId.intValue() : 0,
            performedById != null ? performedById.intValue() : 0,
            notes);
    }

    public AssetHistory create(AssetHistoryRequest req) {
        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_asset_history_create(?, ?, ?, ?, ?, ?, ?)",
            req.getAssetId(),
            req.getEventType(),
            req.getFromOfficeId() != null ? req.getFromOfficeId().intValue() : 0,
            req.getToOfficeId() != null ? req.getToOfficeId().intValue() : 0,
            req.getPerformedById() != null ? req.getPerformedById().intValue() : 0,
            req.getNotes());

        List<AssetHistory> list = jdbcTemplate.query(
            "SELECT h.history_id AS id, h.event_type AS eventType, h.event_date AS eventDate, h.notes, " +
            "a.asset_id, a.property_number AS asset_propertyNumber, a.par_number AS asset_parNumber, " +
            "a.group_id AS asset_groupId, a.serial_number AS asset_serialNumber, " +
            "a.personnel_id AS asset_personnelId, ap.full_name AS asset_accountableName, " +
            "a.current_user_personnel_id AS asset_currentUserId, acu.full_name AS asset_currentUserName, " +
            "a.`description` AS asset_description, " +
            "u.user_id AS pb_id, u.username AS pb_username, u.full_name AS pb_fullName, " +
            "fo.office_id AS fo_id, fo.office_name AS fo_officeName, " +
            "too.office_id AS too_id, too.office_name AS too_officeName " +
            "FROM asset_history h " +
            "LEFT JOIN assets a ON h.asset_id = a.asset_id " +
            "LEFT JOIN personnel ap ON a.personnel_id = ap.personnel_id " +
            "LEFT JOIN personnel acu ON a.current_user_personnel_id = acu.personnel_id " +
            "LEFT JOIN users u ON h.performed_by = u.user_id " +
            "LEFT JOIN offices fo ON h.from_office_id = fo.office_id " +
            "LEFT JOIN offices too ON h.to_office_id = too.office_id " +
            "WHERE h.history_id = ?",
            HISTORY_MAPPER, newId);

        AssetHistory saved = list.isEmpty() ? new AssetHistory() : list.get(0);

        if ("TRANSFERRED".equals(req.getEventType()) && req.getToOfficeId() != null) {
            jdbcTemplate.update(
                "UPDATE assets SET office_id = ?, updated_at = NOW() WHERE asset_id = ? AND is_deleted = 0",
                req.getToOfficeId(), req.getAssetId());
        }

        auditLogService.log("HISTORY_CREATED", "AssetHistory", newId, "asset_history",
            "Event: " + req.getEventType());
        return saved;
    }
}
