package com.sanjose.inventory.controller;

import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.service.AccessService;
import com.sanjose.inventory.service.TransferService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

// Transfer Asset page: admins transfer directly; staff transfers wait for an admin.
@RestController
@RequestMapping("/api/transfers")
@RequiredArgsConstructor
public class TransferController {

    private final TransferService transferService;
    private final AccessService accessService;

    @GetMapping
    public List<TransferService.TransferView> list(@RequestParam(required = false) String status) {
        return transferService.list(status);
    }

    @PostMapping
    public Map<String, Object> submit(@RequestBody TransferService.TransferRequest req) {
        return transferService.submit(req);
    }

    @PostMapping("/{id}/approve")
    public Asset approve(@PathVariable Long id, @RequestBody(required = false) Map<String, String> body) {
        accessService.requireAdmin("approve transfer requests");
        return transferService.approve(id, body != null ? body.get("newParNumber") : null);
    }

    @PostMapping("/{id}/reject")
    public TransferService.TransferView reject(@PathVariable Long id, @RequestBody(required = false) Map<String, String> body) {
        accessService.requireAdmin("reject transfer requests");
        return transferService.reject(id, body != null ? body.get("note") : null);
    }
}
