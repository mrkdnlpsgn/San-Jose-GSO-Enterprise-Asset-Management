package com.sanjose.inventory.service;

import com.sanjose.inventory.entity.DeletedAsset;
import com.sanjose.inventory.entity.DeletedDisposal;
import com.sanjose.inventory.entity.DeletedMaintenance;
import com.sanjose.inventory.repository.DeletedAssetRepository;
import com.sanjose.inventory.repository.DeletedDisposalRepository;
import com.sanjose.inventory.repository.DeletedMaintenanceRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class DeletedRecordsService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;
    private final DeletedAssetRepository deletedAssetRepository;
    private final DeletedMaintenanceRepository deletedMaintenanceRepository;
    private final DeletedDisposalRepository deletedDisposalRepository;

    public List<DeletedAsset> getDeletedAssets() {
        return deletedAssetRepository.findAllByOrderByDeletedAtDesc();
    }

    public List<DeletedMaintenance> getDeletedMaintenance() {
        return deletedMaintenanceRepository.findAllByOrderByDeletedAtDesc();
    }

    public List<DeletedDisposal> getDeletedDisposal() {
        return deletedDisposalRepository.findAllByOrderByDeletedAtDesc();
    }

    // Restoring only ever un-flags the still-intact original row and drops the
    // archive snapshot — assets/maintenance/disposal records are soft-deleted
    // in place, never physically removed, so there's nothing to reconstruct.
    public void restoreAsset(Long deletedAssetId) {
        DeletedAsset snapshot = deletedAssetRepository.findById(deletedAssetId).orElseThrow();
        jdbcTemplate.update("CALL sp_assets_restore(?)", deletedAssetId);
        auditLogService.log("ASSET_RESTORED", "Assets", snapshot.getAssetId(), "asset",
            "Restored: " + snapshot.getPropertyNumber());
    }

    public void restoreMaintenance(Long deletedMaintenanceId) {
        DeletedMaintenance snapshot = deletedMaintenanceRepository.findById(deletedMaintenanceId).orElseThrow();
        jdbcTemplate.update("CALL sp_maintenance_restore(?)", deletedMaintenanceId);
        auditLogService.log("MAINTENANCE_RESTORED", "Maintenance", snapshot.getMaintenanceId(), "maintenance",
            "Restored maintenance record for asset: " + snapshot.getPropertyNumber());
    }

    public void restoreDisposal(Long deletedDisposalId) {
        DeletedDisposal snapshot = deletedDisposalRepository.findById(deletedDisposalId).orElseThrow();
        jdbcTemplate.update("CALL sp_disposal_restore(?)", deletedDisposalId);
        auditLogService.log("DISPOSAL_RESTORED", "Disposal", snapshot.getDisposalId(), "disposal",
            "Restored disposal record for asset: " + snapshot.getPropertyNumber());
    }
}
