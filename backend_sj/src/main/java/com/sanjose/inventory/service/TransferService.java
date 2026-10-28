package com.sanjose.inventory.service;

import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Objects;

// Moving an asset to another office / accountable person (Transfer Asset page); its location
// follows the office.
// An admin's transfer applies immediately; a staff member's becomes a request that an admin
// approves or rejects, like staff maintenance/disposal requests. Every transfer - direct or
// requested - is kept as a row in asset_transfer_requests, so the page can list them.
@Service
@RequiredArgsConstructor
public class TransferService {

    private final JdbcTemplate jdbcTemplate;
    private final AccessService accessService;
    private final AssetService assetService;
    private final AssetHistoryService assetHistoryService;
    private final AuditLogService auditLogService;
    private final SseEmitterService sseEmitterService;
    private final OfficeAssignmentService officeAssignments;
    private final PropertyNumberService propertyNumberService;
    private final AssetQrService assetQrService;
    private final ReturnSlipService returnSlipService;

    // newParNumber: the PAR issued to the new end user, needed when the accountable person changes
    // (an admin types it here; for a staff request, at approval).
    public record TransferRequest(Long assetId, Long toOfficeId, Long toPersonnelId, String toLocation, String reason,
                                  String newParNumber) {}

    public record TransferView(
        Long id, Long assetId, String propertyNumber, String assetDescription,
        Long currentPersonnelId, String currentPersonnelName,
        Long fromOfficeId, String fromOfficeName, Long toOfficeId, String toOfficeName,
        Long toPersonnelId, String toPersonnelName, String toLocation, String reason,
        String status, String reviewNote,
        Long requestedById, String requestedByName, LocalDateTime requestedAt,
        String reviewedByName, LocalDateTime reviewedAt
    ) {}

    // Created here rather than in a migration script so a fresh or hosted database
    // (Render/Aiven, where Hibernate DDL is off) gets it on the next deploy.
    @PostConstruct
    void ensureTable() {
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS asset_transfer_requests (
              transfer_id     INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
              asset_id        INT NOT NULL,
              from_office_id  INT NULL,
              to_office_id    INT NOT NULL,
              to_personnel_id INT NULL,
              to_location     VARCHAR(150) NOT NULL,
              reason          VARCHAR(500) NULL,
              status          VARCHAR(20) NOT NULL DEFAULT 'PENDING_APPROVAL',
              requested_by    INT NULL,
              requested_at    DATETIME NOT NULL,
              reviewed_by     INT NULL,
              reviewed_at     DATETIME NULL,
              review_note     VARCHAR(255) NULL,
              KEY idx_transfer_status (status),
              KEY idx_transfer_asset (asset_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """);
    }

    @Transactional
    public Map<String, Object> submit(TransferRequest req) {
        if (req.assetId() == null) throw new IllegalArgumentException("Choose an asset to transfer.");
        if (req.toOfficeId() == null) throw new IllegalArgumentException("Choose the office to transfer to.");
        String typedLocation = req.toLocation() == null ? "" : req.toLocation().trim();
        if (typedLocation.length() > 150) throw new IllegalArgumentException("Location is too long (150 characters max).");
        String reason = req.reason() == null ? null : req.reason().trim();
        if (reason != null && reason.length() > 500) throw new IllegalArgumentException("Reason is too long (500 characters max).");

        accessService.requireAssetAccess(req.assetId());
        Asset asset = assetService.findById(req.assetId());
        requireOffice(req.toOfficeId());
        // The transfer forms no longer ask for a location: like a newly registered asset, its
        // location becomes its office's name. (Older app versions may still send one.)
        String location = typedLocation.isEmpty() ? officeName(req.toOfficeId()) : typedLocation;
        if (req.toPersonnelId() != null) requirePersonnelInOffice(req.toPersonnelId(), req.toOfficeId());

        AccessService.CurrentUser me = accessService.current();
        Long fromOfficeId = asset.getOffice() != null ? asset.getOffice().getId() : null;
        // Staff sending an asset out of their office must name who takes it over there: the
        // transfer sets the accountable person to exactly this, so none would leave it with nobody.
        boolean leavesOffice = !me.inOffice(req.toOfficeId()) && !Objects.equals(req.toOfficeId(), fromOfficeId);
        if (!me.admin() && leavesOffice && req.toPersonnelId() == null) {
            throw new IllegalArgumentException("Choose the new accountable person. The asset is leaving your office.");
        }
        Long fromPersonnelId = asset.getAccountablePerson() != null ? asset.getAccountablePerson().getId() : null;
        if (Objects.equals(fromOfficeId, req.toOfficeId()) && Objects.equals(fromPersonnelId, req.toPersonnelId())
                && (typedLocation.isEmpty() || location.equalsIgnoreCase(asset.getLocation() == null ? "" : asset.getLocation().trim()))) {
            throw new IllegalArgumentException("Nothing to transfer. The office and accountable person are unchanged.");
        }

        if (!me.admin()) {
            Integer pending = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM asset_transfer_requests WHERE asset_id = ? AND status = 'PENDING_APPROVAL'",
                Integer.class, req.assetId());
            if (pending != null && pending > 0) {
                throw new IllegalStateException("This asset already has a transfer request waiting for approval.");
            }
        }

        jdbcTemplate.update("""
            INSERT INTO asset_transfer_requests
              (asset_id, from_office_id, to_office_id, to_personnel_id, to_location, reason, status, requested_by, requested_at)
            VALUES (?, ?, ?, ?, ?, ?, 'PENDING_APPROVAL', ?, ?)
            """, req.assetId(), fromOfficeId, req.toOfficeId(), req.toPersonnelId(), location, reason, me.id(), now());
        Long transferId = jdbcTemplate.queryForObject("SELECT LAST_INSERT_ID()", Long.class);

        if (me.admin()) {
            Asset result = apply(transferId, me.id(), req.newParNumber());
            return Map.of("status", "APPLIED", "asset", result);
        }
        auditLogService.log("TRANSFER_REQUESTED", "Assets", req.assetId(), "asset",
            "Requested transfer of " + asset.getPropertyNumber() + " to " + officeName(req.toOfficeId()));
        // no asset change yet - "CHANGED" with no data just tells open dashboards to refresh
        sseEmitterService.emitAsset("CHANGED", req.assetId(), null);
        return Map.of("status", "PENDING_APPROVAL", "transfer", findView(transferId));
    }

    public List<TransferView> list(String status) {
        AccessService.CurrentUser me = accessService.current();
        StringBuilder sql = new StringBuilder(VIEW_SQL).append(" WHERE 1=1");
        List<Object> args = new java.util.ArrayList<>();
        if (status != null && !status.isBlank()) { sql.append(" AND t.status = ?"); args.add(status.trim().toUpperCase()); }
        // Staff see the requests they filed; Admin-Staff sees everyone's (but can't review them).
        if (!me.allAssets()) { sql.append(" AND t.requested_by = ?"); args.add(me.id()); }
        sql.append(" ORDER BY t.requested_at DESC LIMIT 100");
        return jdbcTemplate.query(sql.toString(), VIEW_MAPPER, args.toArray());
    }

    @Transactional
    public Asset approve(Long transferId, String newParNumber) {
        accessService.requireAdmin("approve transfer requests");
        TransferView t = findView(transferId);
        if (!"PENDING_APPROVAL".equals(t.status())) throw new IllegalStateException("This request was already " + t.status().toLowerCase() + ".");
        return apply(transferId, accessService.current().id(), newParNumber);
    }

    @Transactional
    public TransferView reject(Long transferId, String note) {
        accessService.requireAdmin("reject transfer requests");
        TransferView t = findView(transferId);
        if (!"PENDING_APPROVAL".equals(t.status())) throw new IllegalStateException("This request was already " + t.status().toLowerCase() + ".");
        String trimmed = note == null ? null : note.trim();
        jdbcTemplate.update("""
            UPDATE asset_transfer_requests SET status = 'REJECTED', reviewed_by = ?, reviewed_at = ?, review_note = ?
            WHERE transfer_id = ?
            """, accessService.current().id(), now(), trimmed == null || trimmed.isEmpty() ? null : trimmed, transferId);
        auditLogService.log("TRANSFER_REJECTED", "Assets", t.assetId(), "asset",
            "Rejected transfer of " + t.propertyNumber() + " to " + t.toOfficeName());
        sseEmitterService.emitAsset("CHANGED", t.assetId(), null);
        return findView(transferId);
    }

    // Moves the asset and records it in Asset History, the audit log and the live feed. When the
    // end user (accountable person) changes, the old one returns the asset on a Property Return
    // Slip and the new one receives it on a new PAR.
    private Asset apply(Long transferId, Long reviewerId, String newParNumber) {
        TransferView t = findView(transferId);
        Asset before = assetService.findById(t.assetId());
        Long fromOfficeId = before.getOffice() != null ? before.getOffice().getId() : null;
        boolean officeChanges = !Objects.equals(fromOfficeId, t.toOfficeId());
        Long fromPersonnelId = before.getAccountablePerson() != null ? before.getAccountablePerson().getId() : null;
        boolean endUserChanges = !Objects.equals(fromPersonnelId, t.toPersonnelId());
        String newPar = null;
        if (endUserChanges && t.toPersonnelId() != null) {
            newPar = assetService.checkNewParNumber(newParNumber, before);
            returnSlipService.requireUnusedPar(newPar);
        }
        Long slipId = endUserChanges && fromPersonnelId != null
            ? returnSlipService.recordReturn(before, transferId, reviewerId) : null;

        jdbcTemplate.update("""
            UPDATE assets SET office_id = ?, personnel_id = ?, location = ?,
              lifecycle_status = CASE WHEN ? THEN 'TRANSFERRED' ELSE lifecycle_status END,
              updated_at = ?
            WHERE asset_id = ?
            """, t.toOfficeId(), t.toPersonnelId(), t.toLocation(), officeChanges, now(), t.assetId());
        jdbcTemplate.update("""
            UPDATE asset_transfer_requests SET status = 'APPROVED', reviewed_by = ?, reviewed_at = ?
            WHERE transfer_id = ?
            """, reviewerId, now(), transferId);

        // the property number's office code follows the asset; its QR sticker must be reprinted
        String newNumber = officeChanges ? propertyNumberService.withOffice(before.getPropertyNumber(), t.toOfficeId()) : before.getPropertyNumber();
        boolean renumbered = !Objects.equals(newNumber, before.getPropertyNumber());
        if (renumbered) {
            jdbcTemplate.update("UPDATE assets SET property_number = ? WHERE asset_id = ?", newNumber, t.assetId());
            assetQrService.reissue(t.assetId(), newNumber);
        }
        if (newPar != null) {
            jdbcTemplate.update("UPDATE assets SET par_number = ? WHERE asset_id = ?", newPar, t.assetId());
            returnSlipService.issuePar(before, assetService.findById(t.assetId()), newPar, t.toPersonnelId(),
                transferId, slipId, reviewerId);
        }

        String note = "Transferred from " + (t.fromOfficeName() != null ? t.fromOfficeName() : "unassigned")
            + " to " + t.toOfficeName() + " (" + t.toLocation() + ")"
            + (t.toPersonnelName() != null ? ", accountable: " + t.toPersonnelName() : "")
            + (t.reason() != null ? ". Reason: " + t.reason() : "")
            + (renumbered ? ". Property number changed from " + before.getPropertyNumber() + " to " + newNumber : "")
            + (slipId != null ? ". Returned by " + before.getAccountablePerson().getFullName() + " on a Property Return Slip" : "")
            + (newPar != null ? ". New PAR " + newPar + (before.getParNumber() != null ? " replaces " + before.getParNumber() : "") : "");
        assetHistoryService.logEvent(t.assetId(), "TRANSFERRED", fromOfficeId, t.toOfficeId(), reviewerId, note);
        auditLogService.log("ASSET_TRANSFERRED", "Assets", t.assetId(), "asset",
            "Transferred " + t.propertyNumber() + " to " + t.toOfficeName());

        Asset result = assetService.findById(t.assetId());
        sseEmitterService.emitAsset("UPDATED", result.getId(), result);
        return result;
    }

    private TransferView findView(Long transferId) {
        List<TransferView> rows = jdbcTemplate.query(VIEW_SQL + " WHERE t.transfer_id = ?", VIEW_MAPPER, transferId);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Transfer request not found.");
        return rows.get(0);
    }

    private void requireOffice(Long officeId) {
        Integer n = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM offices WHERE office_id = ?", Integer.class, officeId);
        if (n == null || n == 0) throw new IllegalArgumentException("That office doesn't exist.");
    }

    private void requirePersonnelInOffice(Long personnelId, Long officeId) {
        Integer exists = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM personnel WHERE personnel_id = ?", Integer.class, personnelId);
        if (exists == null || exists == 0) throw new IllegalArgumentException("That accountable person doesn't exist.");
        if (!officeAssignments.personnelInOffice(personnelId, officeId)) {
            throw new IllegalArgumentException("The accountable person must belong to the office the asset is moving to.");
        }
    }

    private String officeName(Long officeId) {
        List<String> n = jdbcTemplate.query("SELECT office_name FROM offices WHERE office_id = ?",
            (rs, rn) -> rs.getString(1), officeId);
        return n.isEmpty() ? "another office" : n.get(0);
    }

    // DATETIME columns hold UTC (see JacksonTimeConfig).
    private static Timestamp now() {
        return Timestamp.valueOf(LocalDateTime.now(java.time.ZoneOffset.UTC));
    }

    private static final String VIEW_SQL = """
        SELECT t.transfer_id, t.asset_id, a.property_number, a.description,
               a.personnel_id AS current_personnel_id, cp.full_name AS current_personnel_name,
               t.from_office_id, fo.office_name AS from_office_name,
               t.to_office_id, tof.office_name AS to_office_name,
               t.to_personnel_id, p.full_name AS to_personnel_name,
               t.to_location, t.reason, t.status, t.review_note,
               t.requested_by, ru.full_name AS requested_by_name, t.requested_at,
               rv.full_name AS reviewed_by_name, t.reviewed_at
        FROM asset_transfer_requests t
        JOIN assets a        ON a.asset_id = t.asset_id
        LEFT JOIN offices fo  ON fo.office_id = t.from_office_id
        LEFT JOIN offices tof ON tof.office_id = t.to_office_id
        LEFT JOIN personnel p ON p.personnel_id = t.to_personnel_id
        LEFT JOIN personnel cp ON cp.personnel_id = a.personnel_id
        LEFT JOIN users ru    ON ru.user_id = t.requested_by
        LEFT JOIN users rv    ON rv.user_id = t.reviewed_by
        """;

    private static final org.springframework.jdbc.core.RowMapper<TransferView> VIEW_MAPPER = (rs, rn) -> new TransferView(
        rs.getLong("transfer_id"), rs.getLong("asset_id"), rs.getString("property_number"), rs.getString("description"),
        rs.getObject("current_personnel_id", Long.class), rs.getString("current_personnel_name"),
        rs.getObject("from_office_id", Long.class), rs.getString("from_office_name"),
        rs.getLong("to_office_id"), rs.getString("to_office_name"),
        rs.getObject("to_personnel_id", Long.class), rs.getString("to_personnel_name"),
        rs.getString("to_location"), rs.getString("reason"), rs.getString("status"), rs.getString("review_note"),
        rs.getObject("requested_by", Long.class), rs.getString("requested_by_name"),
        rs.getTimestamp("requested_at") != null ? rs.getTimestamp("requested_at").toLocalDateTime() : null,
        rs.getString("reviewed_by_name"),
        rs.getTimestamp("reviewed_at") != null ? rs.getTimestamp("reviewed_at").toLocalDateTime() : null);
}
