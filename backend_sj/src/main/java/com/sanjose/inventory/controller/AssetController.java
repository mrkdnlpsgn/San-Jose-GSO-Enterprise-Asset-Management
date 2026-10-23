package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.AssetImportRow;
import com.sanjose.inventory.dto.AssetOcrResult;
import com.sanjose.inventory.dto.AssetRequest;
import com.sanjose.inventory.dto.EvidencePhotoResponse;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.service.AssetOcrService;
import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.ActionOtpService;
import com.sanjose.inventory.service.AssetService;
import com.sanjose.inventory.exception.ForbiddenException;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import com.sanjose.inventory.service.AssetQrService;
import com.sanjose.inventory.service.AuditLogService;
import com.sanjose.inventory.service.EvidenceService;
import com.sanjose.inventory.service.QrCodeService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/api/assets")
@RequiredArgsConstructor
public class AssetController {

    private final AssetService assetService;
    private final QrCodeService qrCodeService;
    private final AssetOcrService assetOcrService;
    private final EvidenceService evidenceService;
    private final AccessService accessService;
    private final AssetQrService assetQrService;
    private final AuditLogService auditLogService;
    private final ActionOtpService actionOtpService;

    // view=summary returns only what the web lists need (about a fifth of the size): the full
    // records carry specs, remarks, QR data and each office's head user, which the asset view and
    // the edit form load one asset at a time (GET /{id}). Without it the full records come back,
    // as the mobile app and the reports expect.
    @GetMapping
    public List<?> getAll(@RequestParam(required = false) String search,
                           @RequestParam(defaultValue = "0") int page,
                           @RequestParam(defaultValue = "20") int size,
                           @RequestParam(required = false) Long categoryId,
                           @RequestParam(required = false) Long officeId,
                           @RequestParam(required = false) String condition,
                           @RequestParam(required = false) String lifecycleStatus,
                           @RequestParam(required = false) String view) {
        Set<Long> visible = accessService.visibleAssetIds();
        List<Asset> list;
        if (visible == null) {
            list = assetService.findAll(search, page, size, categoryId, officeId, condition, lifecycleStatus);
        } else {
            List<Asset> own = ownAssets(search, categoryId, condition, lifecycleStatus, visible);
            int from = (int) Math.min((long) page * size, own.size());
            list = own.subList(from, (int) Math.min((long) from + size, own.size()));
        }
        return "summary".equalsIgnoreCase(view) ? list.stream().map(AssetController::summary).toList() : list;
    }

    private static Map<String, Object> summary(Asset a) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", a.getId());
        m.put("propertyNumber", a.getPropertyNumber());
        m.put("parNumber", a.getParNumber());
        m.put("serialNumber", a.getSerialNumber());
        m.put("description", a.getDescription());
        m.put("category", a.getCategory() == null ? null : ref("categoryName", a.getCategory().getId(), a.getCategory().getCategoryName()));
        m.put("office", a.getOffice() == null ? null : ref("officeName", a.getOffice().getId(), a.getOffice().getOfficeName()));
        m.put("accountablePerson", a.getAccountablePerson() == null ? null : ref("fullName", a.getAccountablePerson().getId(), a.getAccountablePerson().getFullName()));
        m.put("currentUser", a.getCurrentUser() == null ? null : ref("fullName", a.getCurrentUser().getId(), a.getCurrentUser().getFullName()));
        m.put("condition", a.getCondition());
        m.put("lifecycleStatus", a.getLifecycleStatus());
        m.put("unitValue", a.getUnitValue());
        m.put("quantity", a.getQuantity());
        m.put("acquisitionDate", a.getAcquisitionDate());
        m.put("createdAt", a.getCreatedAt());
        return m;
    }

    private static Map<String, Object> ref(String nameKey, Long id, String name) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", id);
        m.put(nameKey, name);
        return m;
    }

    @GetMapping("/count")
    public long count(@RequestParam(required = false) String search,
                       @RequestParam(required = false) Long categoryId,
                       @RequestParam(required = false) Long officeId,
                       @RequestParam(required = false) String condition,
                       @RequestParam(required = false) String lifecycleStatus) {
        Set<Long> visible = accessService.visibleAssetIds();
        if (visible == null) return assetService.count(search, categoryId, officeId, condition, lifecycleStatus);
        return ownAssets(search, categoryId, condition, lifecycleStatus, visible).size();
    }

    // A staff account's assets (see AccessService): the office query narrows the list down, then
    // only the ones it is the accountable person for are kept. The page is cut from these, so a
    // page and the count always agree. An office filter from staff is ignored.
    private List<Asset> ownAssets(String search, Long categoryId, String condition, String lifecycleStatus, Set<Long> visible) {
        if (visible.isEmpty()) return List.of();
        return assetService.findAll(search, 0, Integer.MAX_VALUE, categoryId, accessService.scopeOfficeId(), condition, lifecycleStatus)
            .stream().filter(a -> visible.contains(a.getId())).toList();
    }

    @GetMapping("/{id}")
    public Asset getById(@PathVariable Long id) {
        accessService.requireAssetAccess(id);
        return assetService.findById(id);
    }

    // All devices of one group (same-model assets added together).
    @GetMapping("/group/{groupId}")
    public List<Asset> getGroup(@PathVariable String groupId) {
        Set<Long> visible = accessService.visibleAssetIds();
        return assetService.findByGroup(groupId).stream()
            .filter(a -> visible == null || visible.contains(a.getId()))
            .toList();
    }

    // Signed payload `asset:{id}:{propertyNumber}:{tag}` (see AssetQrService) - the same text the
    // web and mobile apps print from the asset's qrPayload, so stickers from any source match.
    @GetMapping(value = "/{id}/qr", produces = MediaType.IMAGE_PNG_VALUE)
    public ResponseEntity<byte[]> getQrCode(@PathVariable Long id,
                                            @RequestParam(defaultValue = "300") int size) {
        accessService.requireAssetAccess(id);
        Asset asset = assetService.findById(id);
        int clampedSize = Math.min(Math.max(size, 64), 1000);
        byte[] png = qrCodeService.generatePng(asset.getQrPayload(), clampedSize);
        return ResponseEntity.ok()
            .cacheControl(CacheControl.noStore())
            .contentType(MediaType.IMAGE_PNG)
            .body(png);
    }

    // Bulk QR printing: the sticker data (signed QR text, property number) of the chosen assets,
    // in the order given. Capped so one request stays small; logged like any other print run.
    public record StickerRequest(List<Long> ids) {}

    @PostMapping("/qr-stickers")
    public List<Map<String, Object>> qrStickers(@RequestBody StickerRequest body) {
        List<Long> ids = body.ids() == null ? List.of() : body.ids().stream().filter(java.util.Objects::nonNull).distinct().toList();
        if (ids.isEmpty()) throw new IllegalArgumentException("Choose at least one asset.");
        if (ids.size() > 1000) throw new IllegalArgumentException("Print at most 1,000 QR codes at a time.");
        List<Map<String, Object>> stickers = assetQrService.stickers(ids, accessService.staffScope());
        auditLogService.log("ASSET_QR_BULK_EXPORT", "Assets", null, "asset",
            "Exported QR codes for " + stickers.size() + " asset" + (stickers.size() == 1 ? "" : "s"));
        return stickers;
    }

    // Checks a scanned sticker: VERIFIED (printed by this system, current), UNSIGNED (an older
    // sticker from before signing), INVALID (made up, edited, or replaced by a reissued one), or
    // NOT_FOUND. Answers only the status and id, so it reveals nothing about assets outside the
    // scanner's office; the asset itself is looked up as usual. Failed checks go to the audit log.
    @GetMapping("/verify-qr")
    public Map<String, Object> verifyQr(@RequestParam String code) {
        AssetQrService.ParsedCode parsed = assetQrService.parse(code);
        if (parsed == null) throw new IllegalArgumentException("This is not an asset QR code.");
        AssetQrService.Status status;
        try {
            Asset asset = assetService.findById(parsed.assetId());
            status = assetQrService.check(parsed, asset.getPropertyNumber(), asset.getSha256Hash());
        } catch (ResourceNotFoundException e) {
            status = AssetQrService.Status.NOT_FOUND;
        }
        if (status == AssetQrService.Status.INVALID) {
            auditLogService.log("ASSET_QR_INVALID", "Assets", parsed.assetId(), "asset",
                "Scanned a QR code that failed verification for asset #" + parsed.assetId()
                    + " (property no. on sticker: " + parsed.propertyNumber() + ")");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("status", status.name());
        result.put("assetId", parsed.assetId());
        return result;
    }

    // Retires the asset's current sticker (lost or stolen): older stickers stop verifying.
    @PostMapping("/{id}/qr/reissue")
    public Asset reissueQr(@PathVariable Long id) {
        accessService.requireAdmin("reissue QR codes");
        return assetService.reissueQr(id);
    }

    @PostMapping
    public Asset create(@RequestBody AssetRequest req) {
        accessService.requireAdmin("add assets");
        return assetService.create(req);
    }

    // Reads a photo of an asset tag/sticker (device name + serial number) via
    // Gemini vision to pre-fill the Add Asset form - nothing is saved here,
    // the image is processed in memory and discarded.
    @PostMapping(value = "/scan-label", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public AssetOcrResult scanLabel(@RequestParam("file") MultipartFile file) {
        accessService.requireAdmin("add assets");
        return assetOcrService.scan(file);
    }

    // Bulk create from a parsed spreadsheet (see AssetImportRow) - create-only,
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
        Asset current = assetService.findById(id);
        boolean statusChanges = changesStatus(current, req.getCondition(), req.getLifecycleStatus())
            || (req.getUnits() != null && req.getUnits().stream().anyMatch(u -> changesStatus(current, u.getCondition(), null)));
        if (statusChanges) actionOtpService.require("change the status of " + current.getPropertyNumber());
        if (accessService.isAdmin()) return assetService.update(id, req);
        StaffRequest requested = limitStaffEdit(id, req);
        Asset result = assetService.update(id, req);
        return withRequest(id, requested, result);
    }

    // Condition/lifecycle only - used by the QR scanner's "Update Status".
    @PutMapping("/{id}/status")
    public Asset updateStatus(@PathVariable Long id, @RequestBody Map<String, String> body) {
        accessService.requireAssetAccess(id);
        Asset current = assetService.findById(id);
        if (changesStatus(current, body.get("condition"), body.get("lifecycleStatus"))) {
            actionOtpService.require("change the status of " + current.getPropertyNumber());
        }
        if (accessService.isAdmin()) return assetService.updateStatus(id, body.get("condition"), body.get("lifecycleStatus"));
        Asset before = assetService.findById(id);
        StaffRequest requested = staffRequest(before, body.get("condition"), body.get("lifecycleStatus"));
        String condition = requested != null ? name(before.getCondition()) : body.get("condition");
        String lifecycle = requested != null ? name(before.getLifecycleStatus()) : body.get("lifecycleStatus");
        Asset result = assetService.updateStatus(id, condition, lifecycle);
        return withRequest(id, requested, result);
    }

    // What a staff edit asks for that needs an admin: the lifecycle it should move to
    // (UNDER_MAINTENANCE / DISPOSED) and the condition it asked for, if that changed.
    private record StaffRequest(String lifecycle, String condition) {}

    private static String name(Enum<?> e) { return e != null ? e.name() : null; }

    // Would this edit change the asset's condition or lifecycle status? (Blank = left as is.)
    // Such a change, by staff (as a request) or by an admin, needs an emailed code first.
    private static boolean changesStatus(Asset current, String condition, String lifecycle) {
        return differs(name(current.getCondition()), condition) || differs(name(current.getLifecycleStatus()), lifecycle);
    }

    private static boolean differs(String current, String asked) {
        return asked != null && !asked.isBlank() && !asked.trim().equalsIgnoreCase(current);
    }

    // Putting an asset under maintenance or up for disposal - by picking that status, or by
    // marking it REPAIRABLE / UNSERVICEABLE - is a request: the asset keeps its condition
    // and status until an admin approves. Returns null when nothing needs approval.
    private StaffRequest staffRequest(Asset before, String askedCondition, String askedLifecycle) {
        String conditionBefore = name(before.getCondition());
        String condition = askedCondition == null || askedCondition.isBlank()
            ? conditionBefore : askedCondition.trim().toUpperCase();
        String heldCondition = !java.util.Objects.equals(condition, conditionBefore)
            && ("REPAIRABLE".equals(condition) || "UNSERVICEABLE".equals(condition)) ? condition : null;
        String lifecycle = limitStaffLifecycle(before, askedLifecycle, condition);
        if (lifecycle == null && heldCondition != null) {
            lifecycle = "REPAIRABLE".equals(heldCondition) ? "UNDER_MAINTENANCE" : "DISPOSED";
        }
        return lifecycle != null ? new StaffRequest(lifecycle, heldCondition) : null;
    }

    // Files the staff's maintenance/disposal request (if any) once the edit is saved, and
    // flags the response so the client can say a request is waiting.
    private Asset withRequest(Long id, StaffRequest requested, Asset result) {
        if (requested != null) assetService.requestLifecycleChange(id, requested.lifecycle(), requested.condition());
        String pending = assetService.pendingRequestKind(id);
        if (pending == null) return result;
        Asset fresh = assetService.findById(id);
        fresh.setPendingRequest(pending);
        return fresh;
    }

    // Staff edit their office's assets but can't move one to another office (that takes it
    // out of their scope) or add devices (adding assets is admin-only).
    // Returns what the edit asks for that becomes a request (see staffRequest), else null.
    private StaffRequest limitStaffEdit(Long id, AssetRequest req) {
        Asset before = assetService.findById(id);
        Long office = before.getOffice() != null ? before.getOffice().getId() : null;
        boolean moves = (req.getOfficeId() != null && !req.getOfficeId().equals(office))
            || (req.getUnits() != null && req.getUnits().stream()
                    .anyMatch(u -> u.getOfficeId() != null && !u.getOfficeId().equals(office)));
        if (moves) throw new ForbiddenException("Only an administrator can move an asset to another office.");
        // the accountable person decides who can see the asset, so only an admin reassigns it
        Long accountable = before.getAccountablePerson() != null ? before.getAccountablePerson().getId() : null;
        boolean reassigns = (req.getPersonnelId() != null && !req.getPersonnelId().equals(accountable))
            || (req.getUnits() != null && req.getUnits().stream()
                    .anyMatch(u -> u.getPersonnelId() != null && !u.getPersonnelId().equals(accountable)));
        if (reassigns) throw new ForbiddenException("Only an administrator can change an asset's accountable person.");
        int qty = req.getQuantity() != null ? req.getQuantity() : 1;
        if (qty > 1 || (req.getUnits() != null && req.getUnits().size() > 1)) {
            throw new ForbiddenException("Only an administrator can add devices to an asset.");
        }
        req.setOfficeId(office);
        StaffRequest requested = staffRequest(before, req.getCondition(), req.getLifecycleStatus());
        // the asset keeps its condition and status until an admin approves the request
        if (requested != null) {
            req.setLifecycleStatus(name(before.getLifecycleStatus()));
            req.setCondition(name(before.getCondition()));
        }
        return requested;
    }

    // Staff can't transfer an asset (admins assign it). Putting it under maintenance or
    // disposing of it comes back as the change to request - an admin approves it.
    private String limitStaffLifecycle(Asset before, String requested, String conditionAfter) {
        if (requested == null || requested.isBlank()) return null;
        String current = before.getLifecycleStatus() != null ? before.getLifecycleStatus().name() : null;
        String next = requested.trim().toUpperCase();
        if (next.equals(current)) return null;
        switch (next) {
            case "TRANSFERRED" -> throw new ForbiddenException("Only an administrator can transfer an asset.");
            case "UNDER_MAINTENANCE" -> { return next; }
            case "DISPOSED" -> {
                String cond = conditionAfter == null ? "" : conditionAfter.trim().toUpperCase();
                if (!cond.equals("REPAIRABLE") && !cond.equals("UNSERVICEABLE")) {
                    throw new IllegalStateException(
                        "Only assets marked REPAIRABLE or UNSERVICEABLE can be disposed. Set the condition first.");
                }
                return next;
            }
            default -> { return null; }
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
