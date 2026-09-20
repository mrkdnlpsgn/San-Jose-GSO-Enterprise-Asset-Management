package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.PersonnelRequest;
import com.sanjose.inventory.entity.Personnel;
import com.sanjose.inventory.service.PersonnelService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/personnel")
@RequiredArgsConstructor
public class PersonnelController {

    private final PersonnelService personnelService;

    @GetMapping
    public List<Personnel> getAll(@RequestParam(required = false) String search) { return personnelService.findAll(search); }

    @GetMapping("/{id}")
    public Personnel getById(@PathVariable Long id) { return personnelService.findById(id); }

    @PostMapping
    public Personnel create(@RequestBody PersonnelRequest req) { return personnelService.create(req); }

    @PutMapping("/{id}")
    public Personnel update(@PathVariable Long id, @RequestBody PersonnelRequest req) {
        return personnelService.update(id, req);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        personnelService.delete(id);
        return ResponseEntity.noContent().build();
    }
}
