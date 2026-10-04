package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.dto.AssetHistoryRequest;
import com.sanjose.inventory.dto.EditRequestView;
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

    // Asset History page. Admin: everything. Staff: every event (by anyone) on the assets
    // they're the accountable person for.
    @GetMapping("/accountable")
    public List<AssetHistory> getAccountable(@RequestParam(required = false) String search) {
        AccessService.CurrentUser me = accessService.current();
        if (me.admin()) return assetHistoryService.findAll(search, null);
        return assetHistoryService.findForAccountable(search, me.id());
    }

    // Staff requests (maintenance/disposal) and their outcome. Admin: anyone's, or one
    // person's via userId. Staff: always just their own.
    @GetMapping("/requests")
    public List<EditRequestView> getRequests(@RequestParam(required = false) Long userId) {
        AccessService.CurrentUser me = accessService.current();
        return assetHistoryService.findRequests(me.admin() ? userId : me.id());
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
