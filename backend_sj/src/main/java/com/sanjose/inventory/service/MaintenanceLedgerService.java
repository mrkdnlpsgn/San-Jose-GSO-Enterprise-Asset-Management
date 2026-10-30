package com.sanjose.inventory.service;

import com.sanjose.inventory.config.AppTime;
import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.MaintenanceItem;
import com.sanjose.inventory.dto.MaintenanceLedgerRequest;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.entity.Personnel;
import com.sanjose.inventory.entity.MaintenanceLedger;
import com.sanjose.inventory.entity.User;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
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
    private final MaintenanceItemService itemService;
    private final MaintenancePhotoService photoService;

    // The completion date is a plain column added here rather than in a migration script, so a
    // hosted database gets it on the next deploy. Records completed before it existed have none.
    @PostConstruct
    void ensureCompletedDateColumn() {
        Integer has = jdbcTemplate.queryForObject("""
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'maintenance_ledger' AND COLUMN_NAME = 'completed_date'
            """, Integer.class);
        if (has == null || has == 0) {
            jdbcTemplate.execute("ALTER TABLE maintenance_ledger ADD COLUMN completed_date DATE NULL");
        }
    }

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
        return withCompletedDates(itemService.attach(jdbcTemplate.query("CALL sp_maintenance_list(?, ?, ?, ?, ?, ?)", MAINT_MAPPER,
            search, size, page * size, maintenanceType, status, officeId)));
    }

    public long count(String search, String maintenanceType, String status, Long officeId) {
        return jdbcTemplate.queryForObject("CALL sp_maintenance_count(?, ?, ?, ?)", Long.class,
            search, maintenanceType, status, officeId);
    }

    public List<MaintenanceLedger> findByAsset(Long assetId) {
        return withCompletedDates(itemService.attach(jdbcTemplate.query("CALL sp_maintenance_get_by_asset(?)", MAINT_MAPPER, assetId)));
    }

    public MaintenanceLedger findById(Long id) {
        List<MaintenanceLedger> list = jdbcTemplate.query(
            "CALL sp_maintenance_get_by_id(?)", MAINT_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Maintenance record not found: " + id);
        return withCompletedDates(itemService.attach(list)).get(0);
    }

    private List<MaintenanceLedger> withCompletedDates(List<MaintenanceLedger> records) {
        if (records.isEmpty()) return records;
        Map<Long, LocalDate> dates = new HashMap<>();
        String marks = String.join(", ", Collections.nCopies(records.size(), "?"));
        jdbcTemplate.query("SELECT maintenance_id, completed_date FROM maintenance_ledger WHERE completed_date IS NOT NULL AND maintenance_id IN (" + marks + ")",
            rs -> { dates.put(rs.getLong(1), rs.getDate(2).toLocalDate()); },
            records.stream().map(MaintenanceLedger::getId).toArray());
        records.forEach(r -> r.setCompletedDate(dates.get(r.getId())));
        return records;
    }

    public MaintenanceLedger create(MaintenanceLedgerRequest req) {
        if ("COMPLETED".equals(req.getStatus())) {
            throw new IllegalArgumentException("Save the record as Ongoing first and add its pre- and post-maintenance photos. "
                + "It can be marked Completed once both are there.");
        }
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long recorderId = getUserIdByUsername(username);
        List<MaintenanceItem> items = itemService.clean(req.getItems());

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_maintenance_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            req.getAssetId(),
            req.getMaintenanceType(),
            req.getFindings(),
            req.getActionsTaken(),
            req.getAssignedTo(),
            req.getMaintenanceDate(),
            costOf(items, req.getCost()),
            req.getStatus(),
            recorderId != null ? recorderId.intValue() : 0);
        if (items != null) itemService.replace(newId, items);

        if (!accessService.isAdmin()) {
            // Staff add records as a request - it waits for an admin to approve it before
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
                : "This request is waiting for an administrator's approval. It can be edited once approved.");
        }
        boolean completed = "COMPLETED".equals(req.getStatus());
        boolean completing = completed && current.getStatus() != MaintenanceLedger.MaintenanceStatus.COMPLETED;
        LocalDate completedDate = completed ? completionDate(req, current) : null;
        List<MaintenanceItem> items = itemService.clean(req.getItems());
        jdbcTemplate.update("CALL sp_maintenance_update(?, ?, ?, ?, ?, ?, ?, ?)",
            id,
            req.getMaintenanceType(),
            req.getFindings(),
            req.getActionsTaken(),
            req.getAssignedTo(),
            req.getMaintenanceDate(),
            costOf(items != null ? items : itemService.forRecord(id), req.getCost()),
            req.getStatus());
        jdbcTemplate.update("UPDATE maintenance_ledger SET completed_date = ? WHERE maintenance_id = ?", completedDate, id);
        List<Long> removedParts = items != null ? itemService.replace(id, items) : List.of();
        // checked against the lines as saved, so new parts count; a failure undoes the save
        if (completing) requireCompletionPhotos(id);
        photoService.deleteForItems(removedParts);
        MaintenanceLedger saved = findById(id);
        auditLogService.log("MAINTENANCE_UPDATED", "Maintenance", id, "maintenance",
            "Updated maintenance for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : ""));
        sseEmitterService.emitMaintenance("UPDATED", saved.getId(), saved);
        return saved;
    }

    // The day the repair was finished: required on the web form; older app versions send none, so
    // it is kept from before or taken as today. It can't be before the maintenance date or in the future.
    private LocalDate completionDate(MaintenanceLedgerRequest req, MaintenanceLedger current) {
        LocalDate date = req.getCompletedDate() != null ? req.getCompletedDate()
            : current.getCompletedDate() != null ? current.getCompletedDate() : AppTime.today();
        if (date.isAfter(AppTime.today())) throw new IllegalArgumentException("The completion date can't be in the future.");
        if (req.getMaintenanceDate() != null && date.isBefore(req.getMaintenanceDate())) {
            throw new IllegalArgumentException("The completion date can't be before the maintenance date.");
        }
        return date;
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
            "Maintenance logged (" + saved.getMaintenanceType() + "): " + saved.getFindings() + ", requested by " + saved.getRequestedByName());
        }
        // a staff edit's condition change (REPAIRABLE / UNSERVICEABLE) was held on the
        // request - the asset takes it only now
        if (saved.getAsset() != null) {
            String requestedCondition = jdbcTemplate.queryForObject(
                "SELECT requested_condition FROM maintenance_ledger WHERE maintenance_id = ?", String.class, id);
            if (requestedCondition != null) {
                jdbcTemplate.update("UPDATE assets SET `condition` = ? WHERE asset_id = ?",
                    requestedCondition, saved.getAsset().getId());
            }
        }
        // the request stood in for putting the asset under maintenance - do that now
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
            "Rejected maintenance request for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : "") + ": " + note.trim());
        sseEmitterService.emitMaintenance("REJECTED", saved.getId(), saved);
        return saved;
    }

    // A repair is marked Completed only with its evidence. When the record lists parts, each part
    // needs a pre-maintenance photo (the damaged part as found) and a post-maintenance photo (the
    // part that replaced it); an additional part, found needed during the repair, only the second.
    // A record without parts needs at least one pre- and one post-maintenance photo of the asset.
    // Records completed by the system (a condition change closing open maintenance) and ones already
    // completed aren't held to it.
    private void requireCompletionPhotos(Long id) {
        List<MaintenanceItem> parts = itemService.forRecord(id).stream().filter(i -> !"LABOR".equals(i.kind())).toList();
        Map<String, Integer> counts = new HashMap<>();
        jdbcTemplate.query("SELECT COALESCE(item_id, 0), stage, COUNT(*) FROM maintenance_photos WHERE maintenance_id = ? AND stage IS NOT NULL GROUP BY 1, 2",
            rs -> { counts.put(rs.getLong(1) + ":" + rs.getString(2), rs.getInt(3)); }, id);

        if (parts.isEmpty()) {
            boolean before = counts.keySet().stream().anyMatch(k -> k.endsWith(":BEFORE"));
            boolean after = counts.keySet().stream().anyMatch(k -> k.endsWith(":AFTER"));
            if (!before || !after) {
                String missing = !before && !after ? "a pre-maintenance and a post-maintenance photo"
                    : !before ? "a pre-maintenance photo" : "a post-maintenance photo";
                throw new IllegalArgumentException("Add " + missing + " before marking this repair Completed (Photos).");
            }
            return;
        }
        List<String> missing = new ArrayList<>();
        for (MaintenanceItem p : parts) {
            boolean before = Boolean.TRUE.equals(p.additional()) || counts.containsKey(p.id() + ":BEFORE");
            boolean after = counts.containsKey(p.id() + ":AFTER");
            if (!before || !after) {
                missing.add(p.particular() + " (" + (!before && !after ? "pre- and post-maintenance" : !before ? "pre-maintenance" : "post-maintenance") + ")");
            }
        }
        if (!missing.isEmpty()) {
            throw new IllegalArgumentException("Add the photos missing for these parts before marking the repair Completed: "
                + String.join(", ", missing) + ".");
        }
    }

    // A record with parts and labor lines costs their sum (the card's "Cost of Repair");
    // one without keeps the cost typed in.
    private static java.math.BigDecimal costOf(List<MaintenanceItem> items, java.math.BigDecimal typed) {
        return items != null && !items.isEmpty() ? MaintenanceItemService.total(items) : typed;
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
