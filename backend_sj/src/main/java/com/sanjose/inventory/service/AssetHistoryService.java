package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.AssetHistoryRequest;
import com.sanjose.inventory.dto.EditRequestView;
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
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
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

    // Same columns as sp_asset_history_get_all. The listing is built here rather than in the
    // stored procedures so an event that moved an asset out of an office (a transfer) still
    // shows for that office after the asset is gone — the procs only match the asset's
    // current office.
    private static final String HISTORY_SELECT = """
        SELECT h.history_id AS id, h.event_type AS eventType, h.event_date AS eventDate, h.notes,
               a.asset_id AS asset_id, a.property_number AS asset_propertyNumber, a.par_number AS asset_parNumber,
               a.group_id AS asset_groupId, a.serial_number AS asset_serialNumber,
               a.personnel_id AS asset_personnelId, ap.full_name AS asset_accountableName,
               a.current_user_personnel_id AS asset_currentUserId, acu.full_name AS asset_currentUserName, a.`description` AS asset_description,
               u.user_id AS pb_id, u.username AS pb_username, u.full_name AS pb_fullName,
               fo.office_id AS fo_id, fo.office_name AS fo_officeName,
               too.office_id AS too_id, too.office_name AS too_officeName
        FROM asset_history h
        LEFT JOIN assets a ON h.asset_id = a.asset_id
        LEFT JOIN personnel ap ON a.personnel_id = ap.personnel_id
        LEFT JOIN personnel acu ON a.current_user_personnel_id = acu.personnel_id
        LEFT JOIN users u ON h.performed_by = u.user_id
        LEFT JOIN offices fo ON h.from_office_id = fo.office_id
        LEFT JOIN offices too ON h.to_office_id = too.office_id
        WHERE 1=1
        """;
    private static final String SEARCH_FILTER = """
         AND (h.event_type LIKE ? OR a.property_number LIKE ? OR a.par_number LIKE ?
              OR a.`description` LIKE ? OR u.full_name LIKE ? OR h.notes LIKE ?)""";
    private static final String OFFICE_FILTER = "a.office_id = ? OR h.from_office_id = ? OR h.to_office_id = ?";

    // officeId null = every office (admin).
    public List<AssetHistory> findAll(String search, Long officeId) {
        StringBuilder sql = new StringBuilder(HISTORY_SELECT);
        List<Object> args = new ArrayList<>();
        if (officeId != null) {
            sql.append(" AND (").append(OFFICE_FILTER).append(")");
            args.addAll(List.of(officeId, officeId, officeId));
        }
        return query(sql, args, search);
    }

    // A staff account's history: every event (by anyone) on the assets it is the accountable
    // person for (through the personnel record(s) linked to the account) or that are in its
    // office, plus events that moved an asset into or out of its office.
    public List<AssetHistory> findForAccountable(String search, Long userId, Long officeId) {
        StringBuilder sql = new StringBuilder(HISTORY_SELECT)
            .append(" AND (a.personnel_id IN (SELECT personnel_id FROM personnel WHERE user_id = ?)");
        List<Object> args = new ArrayList<>(List.of(userId));
        if (officeId != null) {
            sql.append(" OR ").append(OFFICE_FILTER);
            args.addAll(List.of(officeId, officeId, officeId));
        }
        sql.append(")");
        return query(sql, args, search);
    }

    private List<AssetHistory> query(StringBuilder sql, List<Object> args, String search) {
        if (search != null && !search.isBlank()) {
            sql.append(SEARCH_FILTER);
            String like = "%" + search.trim() + "%";
            for (int i = 0; i < 6; i++) args.add(like);
        }
        sql.append(" ORDER BY h.event_date DESC, h.history_id DESC");
        return jdbcTemplate.query(sql.toString(), HISTORY_MAPPER, args.toArray());
    }

    // Maintenance / disposal / transfer requests filed by staff (null requestedById = every
    // requester), newest first, with where each stands — Pending, Approved or Rejected.
    public List<EditRequestView> findRequests(Long requestedById) {
        String select = """
            SELECT '%s' AS kind, r.%s AS record_id, a.asset_id, a.property_number, a.par_number,
                   a.description, r.%s AS detail, r.approval_status, r.review_note,
                   r.created_at, r.reviewed_at, ru.user_id AS requester_id,
                   COALESCE(ru.full_name, ru.username) AS requester_name,
                   COALESCE(rv.full_name, rv.username) AS reviewer_name
            FROM %s r
            JOIN assets a ON a.asset_id = r.asset_id
            JOIN users ru ON ru.user_id = r.requested_by
            LEFT JOIN users rv ON rv.user_id = r.reviewed_by
            WHERE r.requested_by IS NOT NULL AND r.is_deleted = 0 AND (? IS NULL OR r.requested_by = ?)
            """;
        String sql = select.formatted("MAINTENANCE", "maintenance_id", "findings", "maintenance_ledger")
            + " UNION ALL "
            + select.formatted("DISPOSAL", "disposal_id", "reason", "disposal_ledger")
            + " ORDER BY created_at DESC";
        List<EditRequestView> ledgerRequests = jdbcTemplate.query(sql, (rs, rn) -> {
            Timestamp requested = rs.getTimestamp("created_at");
            Timestamp reviewed = rs.getTimestamp("reviewed_at");
            return new EditRequestView(
                rs.getString("kind"), rs.getLong("record_id"), rs.getLong("asset_id"),
                rs.getString("property_number"), rs.getString("par_number"), rs.getString("description"),
                rs.getString("detail"), rs.getString("approval_status"), rs.getString("review_note"),
                requested != null ? requested.toLocalDateTime() : null,
                reviewed != null ? reviewed.toLocalDateTime() : null,
                rs.getLong("requester_id"), rs.getString("requester_name"), rs.getString("reviewer_name"));
        }, requestedById, requestedById, requestedById, requestedById);

        List<EditRequestView> all = new ArrayList<>(ledgerRequests);
        all.addAll(findTransferRequests(requestedById));
        all.sort(Comparator.comparing(EditRequestView::requestedAt,
            Comparator.nullsLast(Comparator.<LocalDateTime>naturalOrder())).reversed());
        return all;
    }

    // Transfer requests from the Transfer Asset page. Only STAFF ones: an admin's transfer
    // applies at once, so it isn't a request. "From → To" is put together here, not in SQL,
    // to stay clear of collation mismatches between string literals and columns.
    private List<EditRequestView> findTransferRequests(Long requestedById) {
        return jdbcTemplate.query("""
            SELECT t.transfer_id, a.asset_id, a.property_number, a.par_number, a.description,
                   fo.office_name AS from_office, tof.office_name AS to_office, t.to_location,
                   t.status, t.review_note, t.requested_at, t.reviewed_at, ru.user_id AS requester_id,
                   COALESCE(ru.full_name, ru.username) AS requester_name,
                   COALESCE(rv.full_name, rv.username) AS reviewer_name
            FROM asset_transfer_requests t
            JOIN assets a ON a.asset_id = t.asset_id
            JOIN users ru ON ru.user_id = t.requested_by AND ru.`role` = 'STAFF'
            LEFT JOIN users rv ON rv.user_id = t.reviewed_by
            LEFT JOIN offices fo ON fo.office_id = t.from_office_id
            LEFT JOIN offices tof ON tof.office_id = t.to_office_id
            WHERE (? IS NULL OR t.requested_by = ?)
            """, (rs, rn) -> {
            String from = rs.getString("from_office");
            String detail = (from != null ? from : "Unassigned") + " → " + rs.getString("to_office")
                + " · " + rs.getString("to_location");
            Timestamp requested = rs.getTimestamp("requested_at");
            Timestamp reviewed = rs.getTimestamp("reviewed_at");
            return new EditRequestView(
                "TRANSFER", rs.getLong("transfer_id"), rs.getLong("asset_id"),
                rs.getString("property_number"), rs.getString("par_number"), rs.getString("description"),
                detail, rs.getString("status"), rs.getString("review_note"),
                requested != null ? requested.toLocalDateTime() : null,
                reviewed != null ? reviewed.toLocalDateTime() : null,
                rs.getLong("requester_id"), rs.getString("requester_name"), rs.getString("reviewer_name"));
        }, requestedById, requestedById);
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
