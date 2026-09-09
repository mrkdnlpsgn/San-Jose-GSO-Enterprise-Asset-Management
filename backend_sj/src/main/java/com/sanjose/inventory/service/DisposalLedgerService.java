package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.DisposalLedgerRequest;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.entity.DisposalLedger;
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
public class DisposalLedgerService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;
    private final AssetHistoryService assetHistoryService;
    private final SseEmitterService sseEmitterService;

    private static final RowMapper<DisposalLedger> DISPOSAL_MAPPER = (rs, rn) -> {
        DisposalLedger d = new DisposalLedger();
        d.setId(rs.getLong("id"));
        d.setReason(rs.getString("reason"));
        d.setInspectionFindings(rs.getString("inspectionFindings"));
        String method = rs.getString("recommendedMethod");
        d.setRecommendedMethod(method != null ? DisposalLedger.DisposalMethod.valueOf(method) : null);
        String status = rs.getString("disposalStatus");
        d.setDisposalStatus(status != null ? DisposalLedger.DisposalStatus.valueOf(status) : null);
        Date inspDate = rs.getDate("inspectionDate");
        d.setInspectionDate(inspDate != null ? inspDate.toLocalDate() : null);
        Timestamp createdTs = rs.getTimestamp("createdAt");
        d.setCreatedAt(createdTs != null ? createdTs.toLocalDateTime() : null);
        Timestamp updatedTs = rs.getTimestamp("updatedAt");
        d.setUpdatedAt(updatedTs != null ? updatedTs.toLocalDateTime() : null);

        Long assetId = rs.getObject("asset_id", Long.class);
        if (assetId != null) {
            Asset a = new Asset();
            a.setId(assetId);
            a.setPropertyNumber(rs.getString("asset_propertyNumber"));
            a.setDescription(rs.getString("asset_description"));
            a.setQuantity(rs.getObject("asset_quantity", Integer.class));
            a.setUnitValue(rs.getBigDecimal("asset_unitValue"));
            Date acqDate = rs.getDate("asset_acquisitionDate");
            a.setAcquisitionDate(acqDate != null ? acqDate.toLocalDate() : null);
            String assetCondition = rs.getString("asset_condition");
            a.setCondition(assetCondition != null ? Asset.AssetCondition.valueOf(assetCondition) : null);
            d.setAsset(a);
        }

        Long rbId = rs.getObject("rb_id", Long.class);
        if (rbId != null) {
            User rb = new User();
            rb.setId(rbId);
            rb.setUsername(rs.getString("rb_username"));
            rb.setFullName(rs.getString("rb_fullName"));
            d.setRecordedBy(rb);
        }

        d.setApprovedBy(rs.getString("approvedBy"));
        d.setAppraisedValue(rs.getBigDecimal("appraisedValue"));
        d.setOrNumber(rs.getString("orNumber"));
        d.setAmount(rs.getBigDecimal("amount"));

        return d;
    };

    public List<DisposalLedger> findAll(String search, int page, int size,
                                         String recommendedMethod, String disposalStatus) {
        return jdbcTemplate.query("CALL sp_disposal_list(?, ?, ?, ?, ?)", DISPOSAL_MAPPER,
            search, size, page * size, recommendedMethod, disposalStatus);
    }

    public List<DisposalLedger> findByAsset(Long assetId) {
        return jdbcTemplate.query("CALL sp_disposal_get_by_asset(?)", DISPOSAL_MAPPER, assetId);
    }

    public DisposalLedger findById(Long id) {
        List<DisposalLedger> list = jdbcTemplate.query(
            "CALL sp_disposal_get_by_id(?)", DISPOSAL_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Disposal record not found: " + id);
        return list.get(0);
    }

    public DisposalLedger create(DisposalLedgerRequest req) {
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long recorderId = getUserIdByUsername(username);

        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_disposal_create(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            req.getAssetId(),
            req.getReason(),
            req.getInspectionFindings(),
            req.getRecommendedMethod(),
            req.getDisposalStatus() != null ? req.getDisposalStatus() : "PENDING",
            req.getInspectionDate(),
            req.getApprovedBy(),
            recorderId != null ? recorderId.intValue() : 0,
            req.getAppraisedValue(),
            req.getOrNumber(),
            req.getAmount());

        DisposalLedger saved = findById(newId);
        assetHistoryService.logEvent(req.getAssetId(), "DISPOSAL", null, null, recorderId,
            "Disposal logged (" + req.getRecommendedMethod() + "): " + req.getReason());
        auditLogService.log("DISPOSAL_CREATED", "Disposal", newId, "disposal",
            "Disposal for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : req.getAssetId()));
        sseEmitterService.emitDisposal("CREATED", saved.getId(), saved);
        return saved;
    }

    public DisposalLedger update(Long id, DisposalLedgerRequest req) {
        findById(id); // throws if not found
        jdbcTemplate.update("CALL sp_disposal_update(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            id,
            req.getReason(),
            req.getInspectionFindings(),
            req.getRecommendedMethod(),
            req.getDisposalStatus() != null ? req.getDisposalStatus() : "PENDING",
            req.getInspectionDate(),
            req.getApprovedBy(),
            req.getAppraisedValue(),
            req.getOrNumber(),
            req.getAmount());
        DisposalLedger saved = findById(id);
        auditLogService.log("DISPOSAL_UPDATED", "Disposal", id, "disposal",
            "Updated disposal for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : ""));
        sseEmitterService.emitDisposal("UPDATED", saved.getId(), saved);
        return saved;
    }

    public void delete(Long id, String deleteReason) {
        DisposalLedger d = findById(id);
        String username = SecurityContextHolder.getContext().getAuthentication().getName();
        Long deleterId = getUserIdByUsername(username);
        jdbcTemplate.update("CALL sp_disposal_soft_delete(?, ?, ?, ?)",
            id,
            deleterId != null ? deleterId.intValue() : 0,
            username,
            deleteReason);
        auditLogService.log("DISPOSAL_DELETED", "Disposal", id, "disposal",
            "Deleted disposal for asset: " + (d.getAsset() != null ? d.getAsset().getPropertyNumber() : ""));
        sseEmitterService.emitDisposal("DELETED", id,
            Map.of("asset", Map.of("propertyNumber", d.getAsset() != null ? d.getAsset().getPropertyNumber() : "")));
    }

    private Long getUserIdByUsername(String username) {
        List<Long> ids = jdbcTemplate.query(
            "CALL sp_users_get_by_username(?)", (rs, rn) -> rs.getLong("id"), username);
        return ids.isEmpty() ? null : ids.get(0);
    }
}
