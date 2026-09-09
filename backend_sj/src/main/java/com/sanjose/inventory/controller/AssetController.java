package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.AssetImportRow;
import com.sanjose.inventory.dto.AssetRequest;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.service.AssetService;
import com.sanjose.inventory.service.QrCodeService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/assets")
@RequiredArgsConstructor
public class AssetController {

    private final AssetService assetService;
    private final QrCodeService qrCodeService;

    @GetMapping
    public List<Asset> getAll(@RequestParam(required = false) String search,
                               @RequestParam(defaultValue = "0") int page,
                               @RequestParam(defaultValue = "20") int size,
                               @RequestParam(required = false) Long categoryId,
                               @RequestParam(required = false) Long officeId,
                               @RequestParam(required = false) String condition,
                               @RequestParam(required = false) String lifecycleStatus) {
        return assetService.findAll(search, page, size, categoryId, officeId, condition, lifecycleStatus);
    }

    @GetMapping("/count")
    public long count(@RequestParam(required = false) String search,
                       @RequestParam(required = false) Long categoryId,
                       @RequestParam(required = false) Long officeId,
                       @RequestParam(required = false) String condition,
                       @RequestParam(required = false) String lifecycleStatus) {
        return assetService.count(search, categoryId, officeId, condition, lifecycleStatus);
    }

    @GetMapping("/{id}")
    public Asset getById(@PathVariable Long id) { return assetService.findById(id); }

    // Payload format (`asset:{id}:{propertyNumber}`) matches the one the mobile app
    // already generates client-side, so codes printed from either source scan the same.
    @GetMapping(value = "/{id}/qr", produces = MediaType.IMAGE_PNG_VALUE)
    public ResponseEntity<byte[]> getQrCode(@PathVariable Long id,
                                            @RequestParam(defaultValue = "300") int size) {
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
    public Asset create(@RequestBody AssetRequest req) { return assetService.create(req); }

    // Bulk create from a parsed spreadsheet (see AssetImportRow) — create-only,
    // one bad row is reported as a failure rather than aborting the batch.
    @PostMapping("/bulk-import")
    public Map<String, Object> bulkImport(@RequestBody List<AssetImportRow> rows) {
        return assetService.bulkImport(rows);
    }

    @PutMapping("/{id}")
    public Asset update(@PathVariable Long id, @RequestBody AssetRequest req) {
        return assetService.update(id, req);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id,
                                       @RequestBody(required = false) Map<String, String> body) {
        String reason = body != null ? body.get("deleteReason") : null;
        assetService.delete(id, reason);
        return ResponseEntity.noContent().build();
    }
}
