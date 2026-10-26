package com.sanjose.inventory.controller;

import com.sanjose.inventory.service.PropertyNumberService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

// Renumbering existing assets to YEAR-MONTH-CATEGORY-SERIAL-OFFICE (admin only, see SecurityConfig).
@RestController
@RequestMapping("/api/property-numbers")
@RequiredArgsConstructor
public class PropertyNumberController {

    private final PropertyNumberService propertyNumberService;

    @GetMapping("/status")
    public Map<String, Object> status() { return propertyNumberService.status(); }

    @PostMapping("/renumber")
    public Map<String, Object> renumber() { return propertyNumberService.renumberAll(); }
}
