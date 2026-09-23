package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.ChangePasswordRequest;
import com.sanjose.inventory.dto.ResetPasswordRequest;
import com.sanjose.inventory.dto.UserRequest;
import com.sanjose.inventory.dto.UserResponse;
import com.sanjose.inventory.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @GetMapping
    public List<UserResponse> getAll(@RequestParam(required = false) String search) { return userService.findAll(search); }

    @GetMapping("/{id}")
    public UserResponse getById(@PathVariable Long id) { return userService.findById(id); }

    @PostMapping
    public UserResponse create(@Valid @RequestBody UserRequest req) { return userService.create(req); }

    @PutMapping("/{id}")
    public UserResponse update(@PathVariable Long id, @Valid @RequestBody UserRequest req) {
        return userService.update(id, req);
    }

    // Accounts are deactivated rather than deleted (see UserService.deactivate).
    @PostMapping("/{id}/deactivate")
    public UserResponse deactivate(@PathVariable Long id,
                                   @RequestBody(required = false) java.util.Map<String, Long> body) {
        return userService.deactivate(id, body != null ? body.get("transferToUserId") : null);
    }

    // Kept for older clients (the mobile app): DELETE now deactivates the account.
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id,
                                       @RequestBody(required = false) java.util.Map<String, Long> body) {
        userService.deactivate(id, body != null ? body.get("transferToUserId") : null);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/{id}/reset-password")
    public ResponseEntity<Void> resetPassword(@PathVariable Long id, @Valid @RequestBody ResetPasswordRequest req) {
        userService.resetPassword(id, req.newPassword());
        return ResponseEntity.ok().build();
    }

    @PutMapping("/me/password")
    public ResponseEntity<Void> changePassword(@AuthenticationPrincipal UserDetails principal,
                                               @Valid @RequestBody ChangePasswordRequest req) {
        userService.changePassword(principal.getUsername(), req.currentPassword(), req.newPassword());
        return ResponseEntity.ok().build();
    }
}
