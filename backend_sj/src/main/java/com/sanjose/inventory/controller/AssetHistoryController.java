package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.dto.AssetHistoryRequest;
import com.sanjose.inventory.entity.AssetHistory;
import com.sanjose.inventory.service.AssetHistoryService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/asset-history")
@RequiredArgsConstructor
public class AssetHistoryController {

    private final AssetHistoryService assetHistoryService;
    private final AccessService accessService;

    @GetMapping
    public List<AssetHistory> getAll(@RequestParam(required = false) String search) {
        return assetHistoryService.findAll(search, accessService.scopeOfficeId());
    }

    @GetMapping("/asset/{assetId}")
    public List<AssetHistory> getByAsset(@PathVariable Long assetId) {
        accessService.requireAssetAccess(assetId);
        return assetHistoryService.findByAsset(assetId);
    }

    @PostMapping
    public AssetHistory create(@RequestBody AssetHistoryRequest req) {
        accessService.requireAssetAccess(req.getAssetId());
        return assetHistoryService.create(req);
    }
}
