package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.PropertyCardService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

// Property Cards exist only for assets that have been transferred. Staff see their own offices' cards.
@RestController
@RequestMapping("/api/property-cards")
@RequiredArgsConstructor
public class PropertyCardController {

    private final PropertyCardService propertyCardService;

    @GetMapping
    public List<PropertyCardService.Card> list() {
        return propertyCardService.list();
    }

    @GetMapping("/{assetId}")
    public PropertyCardService.Card forAsset(@PathVariable Long assetId) {
        return propertyCardService.forAsset(assetId);
    }
}
