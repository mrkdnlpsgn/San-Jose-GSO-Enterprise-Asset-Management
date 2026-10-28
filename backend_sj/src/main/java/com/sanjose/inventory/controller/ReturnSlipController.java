package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.ReturnSlipService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

// Property Return Slips and PARs made by end-user transfers, for printing. Staff see their own offices' assets'.
@RestController
@RequiredArgsConstructor
public class ReturnSlipController {

    private final ReturnSlipService returnSlipService;

    @GetMapping("/api/assets/{assetId}/return-papers")
    public ReturnSlipService.AssetPapers forAsset(@PathVariable Long assetId) {
        return returnSlipService.forAsset(assetId);
    }

    @GetMapping("/api/return-slips/{id}")
    public ReturnSlipService.ReturnSlip slip(@PathVariable Long id) {
        return returnSlipService.slip(id);
    }

    @GetMapping("/api/pars/{id}")
    public ReturnSlipService.ParIssue par(@PathVariable Long id) {
        return returnSlipService.par(id);
    }
}
