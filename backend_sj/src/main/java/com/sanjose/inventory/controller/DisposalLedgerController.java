package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.DisposalLedgerRequest;
import com.sanjose.inventory.entity.DisposalLedger;
import com.sanjose.inventory.service.DisposalLedgerService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/disposal")
@RequiredArgsConstructor
public class DisposalLedgerController {

    private final DisposalLedgerService disposalLedgerService;

    @GetMapping
    public List<DisposalLedger> getAll(@RequestParam(required = false) String search,
                                        @RequestParam(defaultValue = "0") int page,
                                        @RequestParam(defaultValue = "20") int size,
                                        @RequestParam(required = false) String recommendedMethod,
                                        @RequestParam(required = false) String disposalStatus) {
        return disposalLedgerService.findAll(search, page, size, recommendedMethod, disposalStatus);
    }

    @GetMapping("/count")
    public long count(@RequestParam(required = false) String search,
                       @RequestParam(required = false) String recommendedMethod,
                       @RequestParam(required = false) String disposalStatus) {
        return disposalLedgerService.count(search, recommendedMethod, disposalStatus);
    }

    @GetMapping("/{id}")
    public DisposalLedger getById(@PathVariable Long id) {
        return disposalLedgerService.findById(id);
    }

    @GetMapping("/asset/{assetId}")
    public List<DisposalLedger> getByAsset(@PathVariable Long assetId) {
        return disposalLedgerService.findByAsset(assetId);
    }

    @PostMapping
    public DisposalLedger create(@RequestBody DisposalLedgerRequest req) {
        return disposalLedgerService.create(req);
    }

    @PutMapping("/{id}")
    public DisposalLedger update(@PathVariable Long id, @RequestBody DisposalLedgerRequest req) {
        return disposalLedgerService.update(id, req);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id,
                                       @RequestBody(required = false) Map<String, String> body) {
        String reason = body != null ? body.get("deleteReason") : null;
        disposalLedgerService.delete(id, reason);
        return ResponseEntity.noContent().build();
    }
}
