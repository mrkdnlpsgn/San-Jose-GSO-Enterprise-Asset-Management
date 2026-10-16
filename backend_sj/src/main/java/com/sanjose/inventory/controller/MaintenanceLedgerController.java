package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.MaintenanceLedgerRequest;
import com.sanjose.inventory.dto.MaintenancePhotoResponse;
import com.sanjose.inventory.entity.MaintenanceLedger;
import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.ActionOtpService;
import com.sanjose.inventory.service.MaintenanceLedgerService;
import com.sanjose.inventory.service.MaintenancePhotoService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/api/maintenance")
@RequiredArgsConstructor
public class MaintenanceLedgerController {

    private final MaintenanceLedgerService maintenanceLedgerService;
    private final MaintenancePhotoService maintenancePhotoService;
    private final AccessService accessService;
    private final ActionOtpService actionOtpService;

    @GetMapping
    public List<MaintenanceLedger> getAll(@RequestParam(required = false) String search,
                                           @RequestParam(defaultValue = "0") int page,
                                           @RequestParam(defaultValue = "20") int size,
                                           @RequestParam(required = false) String maintenanceType,
                                           @RequestParam(required = false) String status) {
        Set<Long> visible = accessService.visibleAssetIds();
        if (visible == null) return maintenanceLedgerService.findAll(search, page, size, maintenanceType, status, null);
        List<MaintenanceLedger> own = ownRecords(search, maintenanceType, status, visible);
        int from = (int) Math.min((long) page * size, own.size());
        return own.subList(from, (int) Math.min((long) from + size, own.size()));
    }

    @GetMapping("/count")
    public long count(@RequestParam(required = false) String search,
                       @RequestParam(required = false) String maintenanceType,
                       @RequestParam(required = false) String status) {
        Set<Long> visible = accessService.visibleAssetIds();
        if (visible == null) return maintenanceLedgerService.count(search, maintenanceType, status, null);
        return ownRecords(search, maintenanceType, status, visible).size();
    }

    // A staff account's records: those of the assets it may see (see AccessService). The office
    // query narrows them down; the page is cut from what is left, so it agrees with the count.
    private List<MaintenanceLedger> ownRecords(String search, String maintenanceType, String status, Set<Long> visible) {
        if (visible.isEmpty()) return List.of();
        return maintenanceLedgerService.findAll(search, 0, Integer.MAX_VALUE, maintenanceType, status, accessService.scopeOfficeId())
            .stream().filter(r -> r.getAsset() != null && visible.contains(r.getAsset().getId())).toList();
    }

    @GetMapping("/{id}")
    public MaintenanceLedger getById(@PathVariable Long id) {
        accessService.requireMaintenanceAccess(id);
        return maintenanceLedgerService.findById(id);
    }

    @GetMapping("/asset/{assetId}")
    public List<MaintenanceLedger> getByAsset(@PathVariable Long assetId) {
        accessService.requireAssetAccess(assetId);
        return maintenanceLedgerService.findByAsset(assetId);
    }

    @PostMapping
    public MaintenanceLedger create(@RequestBody MaintenanceLedgerRequest req) {
        accessService.requireAssetAccess(req.getAssetId());
        // a staff record is a request to put the asset under maintenance, so it is confirmed by code
        if (!accessService.isAdmin()) actionOtpService.require("send a maintenance request");
        return maintenanceLedgerService.create(req);
    }

    @PutMapping("/{id}")
    public MaintenanceLedger update(@PathVariable Long id, @RequestBody MaintenanceLedgerRequest req) {
        accessService.requireMaintenanceAccess(id);
        return maintenanceLedgerService.update(id, req);
    }

    @PostMapping("/{id}/approve")
    public MaintenanceLedger approve(@PathVariable Long id) {
        accessService.requireAdmin("approve requests");
        actionOtpService.require("approve a maintenance request");
        return maintenanceLedgerService.approve(id);
    }

    @PostMapping("/{id}/reject")
    public MaintenanceLedger reject(@PathVariable Long id, @RequestBody(required = false) Map<String, String> body) {
        accessService.requireAdmin("reject requests");
        String note = body != null ? body.get("note") : null;
        // checked before the code is asked for, so a missing reason doesn't use the code up
        if (note == null || note.isBlank()) throw new IllegalArgumentException("Give a reason for rejecting the request.");
        actionOtpService.require("reject a maintenance request");
        return maintenanceLedgerService.reject(id, note);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id,
                                       @RequestBody(required = false) Map<String, String> body) {
        accessService.requireAdmin("delete maintenance records");
        String reason = body != null ? body.get("deleteReason") : null;
        maintenanceLedgerService.delete(id, reason);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{id}/photos")
    public List<MaintenancePhotoResponse> listPhotos(@PathVariable Long id) {
        accessService.requireMaintenanceAccess(id);
        return maintenancePhotoService.list(id);
    }

    @PostMapping("/{id}/photos")
    public MaintenancePhotoResponse uploadPhoto(@PathVariable Long id, @RequestParam("file") MultipartFile file) {
        accessService.requireMaintenanceAccess(id);
        return maintenancePhotoService.upload(id, file);
    }

    @DeleteMapping("/{id}/photos/{photoId}")
    public ResponseEntity<Void> deletePhoto(@PathVariable Long id, @PathVariable Long photoId) {
        accessService.requireMaintenanceAccess(id);
        maintenancePhotoService.delete(id, photoId);
        return ResponseEntity.noContent().build();
    }
}
