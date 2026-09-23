package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.MaintenanceLedgerRequest;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.entity.Personnel;
import com.sanjose.inventory.entity.MaintenanceLedger;
import com.sanjose.inventory.entity.User;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.sql.Timestamp;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Transactional
public class MaintenanceLedgerService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;
    private final AssetHistoryService assetHistoryService;
    private final SseEmitterService sseEmitterService;
    private final AccessService accessService;

    private static final RowMapper<MaintenanceLedger> MAINT_MAPPER = (rs, rn) -> {
        MaintenanceLedger m = new MaintenanceLedger();
        m.setId(rs.getLong("id"));
        String mType = rs.getString("maintenanceType");
        m.setMaintenanceType(mType != null ? MaintenanceLedger.MaintenanceType.valueOf(mType) : null);
        m.setFindings(rs.getString("findings"));
        m.setActionsTaken(rs.getString("actionsTaken"));
        Date md = rs.getDate("maintenanceDate");
        m.setMaintenanceDate(md != null ? md.toLocalDate() : null);
        m.setCost(rs.getBigDecimal("cost"));
        String status = rs.getString("status");
        m.setStatus(status != null ? MaintenanceLedger.MaintenanceStatus.valueOf(status) : null);
        Timestamp createdTs = rs.getTimestamp("createdAt");
        m.setCreatedAt(createdTs != null ? createdTs.toLocalDateTime() : null);
        Timestamp updatedTs = rs.getTimestamp("updatedAt");
        m.setUpdatedAt(updatedTs != null ? updatedTs.toLocalDateTime() : null);

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
            m.setAsset(a);
        }

        Long rbId = rs.getObject("rb_id", Long.class);
        if (rbId != null) {
            User rb = new User();
            rb.setId(rbId);
            rb.setUsername(rs.getString("rb_username"));
            rb.setFullName(rs.getString("rb_fullName"));
            m.setRecordedBy(rb);
        }

        m.setAssignedTo(rs.getString("assignedTo"));
        m.setApprovalStatus(rs.getString("approvalStatus"));
        m.setReviewNote(rs.getString("reviewNote"));
        m.setRequestedByName(rs.getString("requestedByName"));

        return m;
    };

    public List<MaintenanceLedger> findAll(String search, int page, int size,
                                            String maintenanceType, String status, Long officeId) {
        return jdbcTemplate.query("CALL sp_maintenance_list(?, ?, ?, ?, ?, ?)", MAINT_MAPPER,
            search, size, page * size, maintenanceType, status, officeId);
    }

    public long count(String search, String maintenanceType, String status, Long officeId) {
        return jdbcTemplate.queryForObject("CALL sp_maintenance_count(?, ?, ?, ?)", Long.class,
            search, maintenanceType, status, officeId);
    }

    public List<MaintenanceLedger> findByAsset(Long assetId) {
        return jdbcTemplate.query("CALL sp_maintenance_get_by_asset(?)", MAINT_MAPPER, assetId);
    }

    public MaintenanceLedger findById(Long id) {
        List<MaintenanceLedger> list = jdbcTemplate.query(
            "CALL sp_maintenance_get_by_id(?)", MAINT_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Maintenance record not found: " + id);
        return list.get(0);
    }

    public MaintenanceLedger create(MaintenanceLedgerRequest req) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long recorderId = getUserIdByUsername(username);

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_maintenance_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            req.getAssetId(),
            req.getMaintenanceType(),
            req.getFindings(),
            req.getActionsTaken(),
            req.getAssignedTo(),
            req.getMaintenanceDate(),
            req.getCost(),
            req.getStatus(),
            recorderId != null ? recorderId.intValue() : 0);

        if (!accessService.isAdmin()) {
            // Staff add records as a request — it waits for an admin to approve it before
            // it counts (history entry) or can be edited.
            jdbcTemplate.update("UPDATE maintenance_ledger SET approval_status = 'PENDING_APPROVAL', requested_by = ? WHERE maintenance_id = ?",
                recorderId, newId);
            MaintenanceLedger requested = findById(newId);
            auditLogService.log("MAINTENANCE_REQUESTED", "Maintenance", newId, "maintenance",
                "Maintenance requested for asset: " + (requested.getAsset() != null ? requested.getAsset().getPropertyNumber() : req.getAssetId()));
            sseEmitterService.emitMaintenance("CREATED", requested.getId(), requested);
            return requested;
        }

        MaintenanceLedger saved = findById(newId);
        assetHistoryService.logEvent(req.getAssetId(), "MAINTENANCE", null, null, recorderId,
            "Maintenance logged (" + req.getMaintenanceType() + "): " + req.getFindings());
        auditLogService.log("MAINTENANCE_CREATED", "Maintenance", newId, "maintenance",
            "Maintenance for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : req.getAssetId()));
        sseEmitterService.emitMaintenance("CREATED", saved.getId(), saved);
        return saved;
    }

    public MaintenanceLedger update(Long id, MaintenanceLedgerRequest req) {
        MaintenanceLedger current = findById(id);
        if (!accessService.isAdmin() && !"APPROVED".equals(current.getApprovalStatus())) {
            throw new IllegalStateException("REJECTED".equals(current.getApprovalStatus())
                ? "This request was rejected by an administrator and can't be edited."
                : "This request is waiting for an administrator's approval — it can be edited once approved.");
        }
        jdbcTemplate.update("CALL sp_maintenance_update(?, ?, ?, ?, ?, ?, ?, ?)",
            id,
            req.getMaintenanceType(),
            req.getFindings(),
            req.getActionsTaken(),
            req.getAssignedTo(),
            req.getMaintenanceDate(),
            req.getCost(),
            req.getStatus());
        MaintenanceLedger saved = findById(id);
        auditLogService.log("MAINTENANCE_UPDATED", "Maintenance", id, "maintenance",
            "Updated maintenance for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : ""));
        sseEmitterService.emitMaintenance("UPDATED", saved.getId(), saved);
        return saved;
    }

    public void delete(Long id, String deleteReason) {
        MaintenanceLedger m = findById(id);
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long deleterId = getUserIdByUsername(username);
        jdbcTemplate.update("CALL sp_maintenance_soft_delete(?, ?, ?, ?)",
            id,
            deleterId != null ? deleterId.intValue() : 0,
            username,
            deleteReason);
        auditLogService.log("MAINTENANCE_DELETED", "Maintenance", id, "maintenance",
            "Deleted maintenance for asset: " + (m.getAsset() != null ? m.getAsset().getPropertyNumber() : ""));
        sseEmitterService.emitMaintenance("DELETED", id,
            Map.of("asset", Map.of("propertyNumber", m.getAsset() != null ? m.getAsset().getPropertyNumber() : "")));
    }

    public MaintenanceLedger approve(Long id) {
        MaintenanceLedger rec = requirePending(id);
        Long reviewerId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
        jdbcTemplate.update("UPDATE maintenance_ledger SET approval_status = 'APPROVED', reviewed_by = ?, reviewed_at = NOW(), review_note = NULL WHERE maintenance_id = ?",
            reviewerId, id);
        MaintenanceLedger saved = findById(id);
        if (saved.getAsset() != null) {
            assetHistoryService.logEvent(saved.getAsset().getId(), "MAINTENANCE", null, null, reviewerId,
            "Maintenance logged (" + saved.getMaintenanceType() + "): " + saved.getFindings() + " — requested by " + saved.getRequestedByName());
        }
        // the request stood in for putting the asset under maintenance — do that now
        if (saved.getAsset() != null && !"COMPLETED".equals(String.valueOf(saved.getStatus()))) {
            jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)", saved.getAsset().getId(), "UNDER_MAINTENANCE");
            sseEmitterService.emitAsset("UPDATED", saved.getAsset().getId(), null);
        }
        auditLogService.log("MAINTENANCE_APPROVED", "Maintenance", id, "maintenance",
            "Approved maintenance request for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : ""));
        sseEmitterService.emitMaintenance("APPROVED", saved.getId(), saved);
        return saved;
    }

    public MaintenanceLedger reject(Long id, String note) {
        if (note == null || note.isBlank()) throw new IllegalArgumentException("Give a reason for rejecting the request.");
        requirePending(id);
        Long reviewerId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
        jdbcTemplate.update("UPDATE maintenance_ledger SET approval_status = 'REJECTED', reviewed_by = ?, reviewed_at = NOW(), review_note = ? WHERE maintenance_id = ?",
            reviewerId, note.trim(), id);
        MaintenanceLedger saved = findById(id);
        auditLogService.log("MAINTENANCE_REJECTED", "Maintenance", id, "maintenance",
            "Rejected maintenance request for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : "") + " — " + note.trim());
        sseEmitterService.emitMaintenance("REJECTED", saved.getId(), saved);
        return saved;
    }

    private MaintenanceLedger requirePending(Long id) {
        MaintenanceLedger rec = findById(id);
        if (!"PENDING_APPROVAL".equals(rec.getApprovalStatus())) {
            throw new IllegalStateException("Only requests waiting for approval can be approved or rejected.");
        }
        return rec;
    }

    private Long getUserIdByUsername(String username) {
        List<Long> ids = jdbcTemplate.query(
            "CALL sp_users_get_by_username(?)", (rs, rn) -> rs.getLong("id"), username);
        return ids.isEmpty() ? null : ids.get(0);
    }
}
