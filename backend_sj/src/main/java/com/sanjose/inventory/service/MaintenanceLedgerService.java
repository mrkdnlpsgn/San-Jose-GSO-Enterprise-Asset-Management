package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.MaintenanceLedgerRequest;
import com.sanjose.inventory.entity.Asset;
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

        return m;
    };

    public List<MaintenanceLedger> findAll(String search, int page, int size,
                                            String maintenanceType, String status) {
        return jdbcTemplate.query("CALL sp_maintenance_list(?, ?, ?, ?, ?)", MAINT_MAPPER,
            search, size, page * size, maintenanceType, status);
    }

    public long count(String search, String maintenanceType, String status) {
        return jdbcTemplate.queryForObject("CALL sp_maintenance_count(?, ?, ?)", Long.class,
            search, maintenanceType, status);
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

        MaintenanceLedger saved = findById(newId);
        assetHistoryService.logEvent(req.getAssetId(), "MAINTENANCE", null, null, recorderId,
            "Maintenance logged (" + req.getMaintenanceType() + "): " + req.getFindings());
        auditLogService.log("MAINTENANCE_CREATED", "Maintenance", newId, "maintenance",
            "Maintenance for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : req.getAssetId()));
        sseEmitterService.emitMaintenance("CREATED", saved.getId(), saved);
        return saved;
    }

    public MaintenanceLedger update(Long id, MaintenanceLedgerRequest req) {
        findById(id); // throws if not found
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

    private Long getUserIdByUsername(String username) {
        List<Long> ids = jdbcTemplate.query(
            "CALL sp_users_get_by_username(?)", (rs, rn) -> rs.getLong("id"), username);
        return ids.isEmpty() ? null : ids.get(0);
    }
}
