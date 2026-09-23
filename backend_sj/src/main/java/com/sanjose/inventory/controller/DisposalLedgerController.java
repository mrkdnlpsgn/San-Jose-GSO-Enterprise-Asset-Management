package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.DisposalLedgerRequest;
import com.sanjose.inventory.dto.EvidencePhotoResponse;
import com.sanjose.inventory.entity.DisposalLedger;
import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.DisposalLedgerService;
import com.sanjose.inventory.service.EvidenceService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/disposal")
@RequiredArgsConstructor
public class DisposalLedgerController {

    private final DisposalLedgerService disposalLedgerService;
    private final EvidenceService evidenceService;
    private final AccessService accessService;

    @GetMapping
    public List<DisposalLedger> getAll(@RequestParam(required = false) String search,
                                        @RequestParam(defaultValue = "0") int page,
                                        @RequestParam(defaultValue = "20") int size,
                                        @RequestParam(required = false) String recommendedMethod,
                                        @RequestParam(required = false) String disposalStatus) {
        return disposalLedgerService.findAll(search, page, size, recommendedMethod, disposalStatus, accessService.scopeOfficeId());
    }

    @GetMapping("/count")
    public long count(@RequestParam(required = false) String search,
                       @RequestParam(required = false) String recommendedMethod,
                       @RequestParam(required = false) String disposalStatus) {
        return disposalLedgerService.count(search, recommendedMethod, disposalStatus, accessService.scopeOfficeId());
    }

    // Evidence photos for a disposal record (same behavior as a maintenance record's evidence).
    @GetMapping("/{id}/evidence")
    public List<EvidencePhotoResponse> listEvidence(@PathVariable Long id) {
        accessService.requireDisposalAccess(id);
        return evidenceService.list(EvidenceService.Target.DISPOSAL, id);
    }

    @PostMapping("/{id}/evidence")
    public EvidencePhotoResponse uploadEvidence(@PathVariable Long id, @RequestParam("file") MultipartFile file) {
        accessService.requireDisposalAccess(id);
        return evidenceService.upload(EvidenceService.Target.DISPOSAL, id, file);
    }

    @DeleteMapping("/{id}/evidence/{photoId}")
    public ResponseEntity<Void> deleteEvidence(@PathVariable Long id, @PathVariable Long photoId) {
        accessService.requireDisposalAccess(id);
        evidenceService.delete(EvidenceService.Target.DISPOSAL, id, photoId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{id}")
    public DisposalLedger getById(@PathVariable Long id) {
        accessService.requireDisposalAccess(id);
        return disposalLedgerService.findById(id);
    }

    @GetMapping("/asset/{assetId}")
    public List<DisposalLedger> getByAsset(@PathVariable Long assetId) {
        accessService.requireAssetAccess(assetId);
        return disposalLedgerService.findByAsset(assetId);
    }

    @PostMapping
    public DisposalLedger create(@RequestBody DisposalLedgerRequest req) {
        accessService.requireAssetAccess(req.getAssetId());
        return disposalLedgerService.create(req);
    }

    @PutMapping("/{id}")
    public DisposalLedger update(@PathVariable Long id, @RequestBody DisposalLedgerRequest req) {
        accessService.requireDisposalAccess(id);
        return disposalLedgerService.update(id, req);
    }

    @PostMapping("/{id}/approve")
    public DisposalLedger approve(@PathVariable Long id) {
        accessService.requireAdmin("approve requests");
        return disposalLedgerService.approve(id);
    }

    @PostMapping("/{id}/reject")
    public DisposalLedger reject(@PathVariable Long id, @RequestBody(required = false) Map<String, String> body) {
        accessService.requireAdmin("reject requests");
        return disposalLedgerService.reject(id, body != null ? body.get("note") : null);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id,
                                       @RequestBody(required = false) Map<String, String> body) {
        accessService.requireAdmin("delete disposal records");
        String reason = body != null ? body.get("deleteReason") : null;
        disposalLedgerService.delete(id, reason);
        return ResponseEntity.noContent().build();
    }
}
