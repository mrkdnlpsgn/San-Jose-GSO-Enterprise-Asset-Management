package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.MaintenanceLedgerRequest;
import com.sanjose.inventory.dto.MaintenancePhotoResponse;
import com.sanjose.inventory.entity.MaintenanceLedger;
import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.MaintenanceLedgerService;
import com.sanjose.inventory.service.MaintenancePhotoService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/maintenance")
@RequiredArgsConstructor
public class MaintenanceLedgerController {

    private final MaintenanceLedgerService maintenanceLedgerService;
    private final MaintenancePhotoService maintenancePhotoService;
    private final AccessService accessService;

    @GetMapping
    public List<MaintenanceLedger> getAll(@RequestParam(required = false) String search,
                                           @RequestParam(defaultValue = "0") int page,
                                           @RequestParam(defaultValue = "20") int size,
                                           @RequestParam(required = false) String maintenanceType,
                                           @RequestParam(required = false) String status) {
        return maintenanceLedgerService.findAll(search, page, size, maintenanceType, status, accessService.scopeOfficeId());
    }

    @GetMapping("/count")
    public long count(@RequestParam(required = false) String search,
                       @RequestParam(required = false) String maintenanceType,
                       @RequestParam(required = false) String status) {
        return maintenanceLedgerService.count(search, maintenanceType, status, accessService.scopeOfficeId());
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
        return maintenanceLedgerService.approve(id);
    }

    @PostMapping("/{id}/reject")
    public MaintenanceLedger reject(@PathVariable Long id, @RequestBody(required = false) Map<String, String> body) {
        accessService.requireAdmin("reject requests");
        return maintenanceLedgerService.reject(id, body != null ? body.get("note") : null);
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
