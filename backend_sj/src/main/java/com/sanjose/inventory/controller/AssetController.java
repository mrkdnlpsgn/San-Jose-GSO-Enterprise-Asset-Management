package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.AssetImportRow;
import com.sanjose.inventory.dto.AssetOcrResult;
import com.sanjose.inventory.dto.AssetRequest;
import com.sanjose.inventory.dto.EvidencePhotoResponse;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.service.AssetOcrService;
import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.AssetService;
import com.sanjose.inventory.exception.ForbiddenException;
import com.sanjose.inventory.service.EvidenceService;
import com.sanjose.inventory.service.QrCodeService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/assets")
@RequiredArgsConstructor
public class AssetController {

    private final AssetService assetService;
    private final QrCodeService qrCodeService;
    private final AssetOcrService assetOcrService;
    private final EvidenceService evidenceService;
    private final AccessService accessService;

    @GetMapping
    public List<Asset> getAll(@RequestParam(required = false) String search,
                               @RequestParam(defaultValue = "0") int page,
                               @RequestParam(defaultValue = "20") int size,
                               @RequestParam(required = false) Long categoryId,
                               @RequestParam(required = false) Long officeId,
                               @RequestParam(required = false) String condition,
                               @RequestParam(required = false) String lifecycleStatus) {
        return assetService.findAll(search, page, size, categoryId, scoped(officeId), condition, lifecycleStatus);
    }

    @GetMapping("/count")
    public long count(@RequestParam(required = false) String search,
                       @RequestParam(required = false) Long categoryId,
                       @RequestParam(required = false) Long officeId,
                       @RequestParam(required = false) String condition,
                       @RequestParam(required = false) String lifecycleStatus) {
        return assetService.count(search, categoryId, scoped(officeId), condition, lifecycleStatus);
    }

    // Staff only ever see their own office's assets, whatever office filter they ask for.
    private Long scoped(Long requestedOfficeId) {
        Long scope = accessService.scopeOfficeId();
        return scope != null ? scope : requestedOfficeId;
    }

    @GetMapping("/{id}")
    public Asset getById(@PathVariable Long id) {
        accessService.requireAssetAccess(id);
        return assetService.findById(id);
    }

    // All devices of one group (same-model assets added together).
    @GetMapping("/group/{groupId}")
    public List<Asset> getGroup(@PathVariable String groupId) {
        Long scope = accessService.scopeOfficeId();
        return assetService.findByGroup(groupId).stream()
            .filter(a -> scope == null || (a.getOffice() != null && scope.equals(a.getOffice().getId())))
            .toList();
    }

    // Payload format (`asset:{id}:{propertyNumber}`) matches the one the mobile app
    // already generates client-side, so codes printed from either source scan the same.
    @GetMapping(value = "/{id}/qr", produces = MediaType.IMAGE_PNG_VALUE)
    public ResponseEntity<byte[]> getQrCode(@PathVariable Long id,
                                            @RequestParam(defaultValue = "300") int size) {
        accessService.requireAssetAccess(id);
        Asset asset = assetService.findById(id);
        String payload = "asset:" + asset.getId() + ":" + asset.getPropertyNumber();
        int clampedSize = Math.min(Math.max(size, 64), 1000);
        byte[] png = qrCodeService.generatePng(payload, clampedSize);
        return ResponseEntity.ok()
            .cacheControl(CacheControl.noStore())
            .contentType(MediaType.IMAGE_PNG)
            .body(png);
    }

    @PostMapping
    public Asset create(@RequestBody AssetRequest req) {
        accessService.requireAdmin("add assets");
        return assetService.create(req);
    }

    // Reads a photo of an asset tag/sticker (device name + serial number) via
    // Gemini vision to pre-fill the Add Asset form — nothing is saved here,
    // the image is processed in memory and discarded.
    @PostMapping(value = "/scan-label", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public AssetOcrResult scanLabel(@RequestParam("file") MultipartFile file) {
        accessService.requireAdmin("add assets");
        return assetOcrService.scan(file);
    }

    // Bulk create from a parsed spreadsheet (see AssetImportRow) — create-only,
    // one bad row is reported as a failure rather than aborting the batch.
    @PostMapping("/bulk-import")
    public Map<String, Object> bulkImport(@RequestBody List<AssetImportRow> rows) {
        accessService.requireAdmin("import assets");
        return assetService.bulkImport(rows);
    }

    // Evidence photos for an asset (same behavior as a maintenance record's evidence).
    @GetMapping("/{id}/evidence")
    public List<EvidencePhotoResponse> listEvidence(@PathVariable Long id) {
        accessService.requireAssetAccess(id);
        return evidenceService.list(EvidenceService.Target.ASSET, id);
    }

    @PostMapping("/{id}/evidence")
    public EvidencePhotoResponse uploadEvidence(@PathVariable Long id, @RequestParam("file") MultipartFile file) {
        accessService.requireAssetAccess(id);
        return evidenceService.upload(EvidenceService.Target.ASSET, id, file);
    }

    @DeleteMapping("/{id}/evidence/{photoId}")
    public ResponseEntity<Void> deleteEvidence(@PathVariable Long id, @PathVariable Long photoId) {
        accessService.requireAssetAccess(id);
        evidenceService.delete(EvidenceService.Target.ASSET, id, photoId);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{id}")
    public Asset update(@PathVariable Long id, @RequestBody AssetRequest req) {
        accessService.requireAssetAccess(id);
        if (!accessService.isAdmin()) limitStaffEdit(id, req);
        return assetService.update(id, req);
    }

    // Condition/lifecycle only — used by the QR scanner's "Update Status".
    @PutMapping("/{id}/status")
    public Asset updateStatus(@PathVariable Long id, @RequestBody Map<String, String> body) {
        accessService.requireAssetAccess(id);
        if (!accessService.isAdmin()) limitStaffLifecycle(assetService.findById(id), body.get("lifecycleStatus"));
        return assetService.updateStatus(id, body.get("condition"), body.get("lifecycleStatus"));
    }

    // Staff edit their office's assets but can't move one to another office (that takes it
    // out of their scope) or add devices (adding assets is admin-only).
    private void limitStaffEdit(Long id, AssetRequest req) {
        Asset before = assetService.findById(id);
        Long office = before.getOffice() != null ? before.getOffice().getId() : null;
        boolean moves = (req.getOfficeId() != null && !req.getOfficeId().equals(office))
            || (req.getUnits() != null && req.getUnits().stream()
                    .anyMatch(u -> u.getOfficeId() != null && !u.getOfficeId().equals(office)));
        if (moves) throw new ForbiddenException("Only an administrator can move an asset to another office.");
        int qty = req.getQuantity() != null ? req.getQuantity() : 1;
        if (qty > 1 || (req.getUnits() != null && req.getUnits().size() > 1)) {
            throw new ForbiddenException("Only an administrator can add devices to an asset.");
        }
        req.setOfficeId(office);
        limitStaffLifecycle(before, req.getLifecycleStatus());
    }

    // Staff can't transfer an asset (admins assign it), and put it under maintenance or
    // dispose of it only through a maintenance / disposal request an admin approves.
    private void limitStaffLifecycle(Asset before, String requested) {
        if (requested == null || requested.isBlank()) return;
        String current = before.getLifecycleStatus() != null ? before.getLifecycleStatus().name() : null;
        String next = requested.trim().toUpperCase();
        if (next.equals(current)) return;
        switch (next) {
            case "TRANSFERRED" -> throw new ForbiddenException("Only an administrator can transfer an asset.");
            case "UNDER_MAINTENANCE" -> throw new ForbiddenException(
                "Send a maintenance request instead — an administrator approves it.");
            case "DISPOSED" -> throw new ForbiddenException(
                "Send a disposal request instead — an administrator approves it.");
            default -> { }
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id,
                                       @RequestBody(required = false) Map<String, String> body) {
        accessService.requireAdmin("delete assets");
        String reason = body != null ? body.get("deleteReason") : null;
        assetService.delete(id, reason);
        return ResponseEntity.noContent().build();
    }
}
