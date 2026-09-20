package com.sanjose.inventory.controller;

import com.sanjose.inventory.entity.DeletedAsset;
import com.sanjose.inventory.entity.DeletedDisposal;
import com.sanjose.inventory.entity.DeletedMaintenance;
import com.sanjose.inventory.service.DeletedRecordsService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/deleted-records")
@RequiredArgsConstructor
public class DeletedRecordsController {

    private final DeletedRecordsService deletedRecordsService;

    @GetMapping("/assets")
    public List<DeletedAsset> getDeletedAssets() {
        return deletedRecordsService.getDeletedAssets();
    }

    @GetMapping("/maintenance")
    public List<DeletedMaintenance> getDeletedMaintenance() {
        return deletedRecordsService.getDeletedMaintenance();
    }

    @GetMapping("/disposal")
    public List<DeletedDisposal> getDeletedDisposal() {
        return deletedRecordsService.getDeletedDisposal();
    }

    @PostMapping("/assets/{id}/restore")
    public ResponseEntity<Void> restoreAsset(@PathVariable Long id) {
        deletedRecordsService.restoreAsset(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/maintenance/{id}/restore")
    public ResponseEntity<Void> restoreMaintenance(@PathVariable Long id) {
        deletedRecordsService.restoreMaintenance(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/disposal/{id}/restore")
    public ResponseEntity<Void> restoreDisposal(@PathVariable Long id) {
        deletedRecordsService.restoreDisposal(id);
        return ResponseEntity.noContent().build();
    }

    // Each permanent-delete call requires the OTP requested via
    // POST /api/auth/delete-otp/request — verified inline (see
    // DeletedRecordsService), not via a separate standalone verify endpoint.
    @PostMapping("/assets/{id}/permanent-delete")
    public ResponseEntity<Void> permanentDeleteAsset(@PathVariable Long id, @RequestBody Map<String, String> body) {
        deletedRecordsService.permanentDeleteAsset(id, body.get("otp"));
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/maintenance/{id}/permanent-delete")
    public ResponseEntity<Void> permanentDeleteMaintenance(@PathVariable Long id, @RequestBody Map<String, String> body) {
        deletedRecordsService.permanentDeleteMaintenance(id, body.get("otp"));
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/disposal/{id}/permanent-delete")
    public ResponseEntity<Void> permanentDeleteDisposal(@PathVariable Long id, @RequestBody Map<String, String> body) {
        deletedRecordsService.permanentDeleteDisposal(id, body.get("otp"));
        return ResponseEntity.noContent().build();
    }
}
