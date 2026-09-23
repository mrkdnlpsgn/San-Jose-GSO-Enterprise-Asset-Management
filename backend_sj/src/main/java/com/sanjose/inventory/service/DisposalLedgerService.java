package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.DisposalLedgerRequest;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.entity.Personnel;
import com.sanjose.inventory.entity.Category;
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
    private final AccessService accessService;

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
            a.setQuantity(rs.getObject("asset_quantity", Integer.class));
            a.setUnitValue(rs.getBigDecimal("asset_unitValue"));
            Date acqDate = rs.getDate("asset_acquisitionDate");
            a.setAcquisitionDate(acqDate != null ? acqDate.toLocalDate() : null);
            String assetCondition = rs.getString("asset_condition");
            a.setCondition(assetCondition != null ? Asset.AssetCondition.valueOf(assetCondition) : null);

            Long catId = rs.getObject("asset_category_id", Long.class);
            if (catId != null) {
                Category c = new Category();
                c.setId(catId);
                c.setCategoryName(rs.getString("asset_category_name"));
                a.setCategory(c);
            }

            d.setAsset(a);

            Integer usefulLifeYears = rs.getObject("asset_categoryUsefulLifeYears", Integer.class);
            DepreciationCalculator.Result result = DepreciationCalculator.compute(
                a.getUnitValue(), a.getAcquisitionDate(), usefulLifeYears);
            if (result != null) {
                a.setAccumulatedDepreciation(result.accumulatedDepreciation());
                a.setCarryingAmount(result.carryingAmount());
                d.setAccumulatedDepreciation(result.accumulatedDepreciation());
                d.setCarryingAmount(result.carryingAmount());
            }
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
        d.setApprovalStatus(rs.getString("approvalStatus"));
        d.setReviewNote(rs.getString("reviewNote"));
        d.setRequestedByName(rs.getString("requestedByName"));

        return d;
    };

    public List<DisposalLedger> findAll(String search, int page, int size,
                                         String recommendedMethod, String disposalStatus, Long officeId) {
        return jdbcTemplate.query("CALL sp_disposal_list(?, ?, ?, ?, ?, ?)", DISPOSAL_MAPPER,
            search, size, page * size, recommendedMethod, disposalStatus, officeId);
    }

    public long count(String search, String recommendedMethod, String disposalStatus, Long officeId) {
        return jdbcTemplate.queryForObject("CALL sp_disposal_count(?, ?, ?, ?)", Long.class,
            search, recommendedMethod, disposalStatus, officeId);
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
        List<String> conditions = jdbcTemplate.query(
            "SELECT `condition` FROM assets WHERE asset_id = ?",
            (rs, rn) -> rs.getString("condition"), req.getAssetId());
        if (conditions.isEmpty()) {
            throw new ResourceNotFoundException("Asset not found: " + req.getAssetId());
        }
        String assetCondition = conditions.get(0);
        if (!"REPAIRABLE".equals(assetCondition) && !"UNSERVICEABLE".equals(assetCondition)) {
            throw new IllegalStateException(
                "Asset cannot be disposed while its condition is SERVICEABLE — " +
                "mark it REPAIRABLE or UNSERVICEABLE first (via a physical inspection).");
        }

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

        if (!accessService.isAdmin()) {
            // Staff add records as a request — it waits for an admin to approve it before
            // it counts (history entry) or can be edited.
            jdbcTemplate.update("UPDATE disposal_ledger SET approval_status = 'PENDING_APPROVAL', requested_by = ? WHERE disposal_id = ?",
                recorderId, newId);
            DisposalLedger requested = findById(newId);
            auditLogService.log("DISPOSAL_REQUESTED", "Disposal", newId, "disposal",
                "Disposal requested for asset: " + (requested.getAsset() != null ? requested.getAsset().getPropertyNumber() : req.getAssetId()));
            sseEmitterService.emitDisposal("CREATED", requested.getId(), requested);
            return requested;
        }

        DisposalLedger saved = findById(newId);
        assetHistoryService.logEvent(req.getAssetId(), "DISPOSAL", null, null, recorderId,
            "Disposal logged (" + req.getRecommendedMethod() + "): " + req.getReason());
        auditLogService.log("DISPOSAL_CREATED", "Disposal", newId, "disposal",
            "Disposal for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : req.getAssetId()));
        sseEmitterService.emitDisposal("CREATED", saved.getId(), saved);
        return saved;
    }

    public DisposalLedger update(Long id, DisposalLedgerRequest req) {
        DisposalLedger current = findById(id);
        if (!accessService.isAdmin() && !"APPROVED".equals(current.getApprovalStatus())) {
            throw new IllegalStateException("REJECTED".equals(current.getApprovalStatus())
                ? "This request was rejected by an administrator and can't be edited."
                : "This request is waiting for an administrator's approval — it can be edited once approved.");
        }
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

    public DisposalLedger approve(Long id) {
        DisposalLedger rec = requirePending(id);
        Long reviewerId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
        jdbcTemplate.update("UPDATE disposal_ledger SET approval_status = 'APPROVED', reviewed_by = ?, reviewed_at = NOW(), review_note = NULL WHERE disposal_id = ?",
            reviewerId, id);
        DisposalLedger saved = findById(id);
        if (saved.getAsset() != null) {
            assetHistoryService.logEvent(saved.getAsset().getId(), "DISPOSAL", null, null, reviewerId,
            "Disposal logged (" + saved.getRecommendedMethod() + "): " + saved.getReason() + " — requested by " + saved.getRequestedByName());
        }
        // the request stood in for putting the asset up for disposal — do that now
        if (saved.getAsset() != null && true) {
            jdbcTemplate.update("CALL sp_assets_update_lifecycle(?, ?)", saved.getAsset().getId(), "DISPOSED");
            sseEmitterService.emitAsset("UPDATED", saved.getAsset().getId(), null);
        }
        auditLogService.log("DISPOSAL_APPROVED", "Disposal", id, "disposal",
            "Approved disposal request for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : ""));
        sseEmitterService.emitDisposal("APPROVED", saved.getId(), saved);
        return saved;
    }

    public DisposalLedger reject(Long id, String note) {
        if (note == null || note.isBlank()) throw new IllegalArgumentException("Give a reason for rejecting the request.");
        requirePending(id);
        Long reviewerId = getUserIdByUsername(SecurityContextHolder.getContext().getAuthentication().getName());
        jdbcTemplate.update("UPDATE disposal_ledger SET approval_status = 'REJECTED', reviewed_by = ?, reviewed_at = NOW(), review_note = ? WHERE disposal_id = ?",
            reviewerId, note.trim(), id);
        DisposalLedger saved = findById(id);
        auditLogService.log("DISPOSAL_REJECTED", "Disposal", id, "disposal",
            "Rejected disposal request for asset: " + (saved.getAsset() != null ? saved.getAsset().getPropertyNumber() : "") + " — " + note.trim());
        sseEmitterService.emitDisposal("REJECTED", saved.getId(), saved);
        return saved;
    }

    private DisposalLedger requirePending(Long id) {
        DisposalLedger rec = findById(id);
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
