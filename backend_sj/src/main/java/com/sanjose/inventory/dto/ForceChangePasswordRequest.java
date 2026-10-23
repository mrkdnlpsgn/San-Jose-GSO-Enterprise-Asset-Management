package com.sanjose.inventory.dto;

import com.sanjose.inventory.validation.StrongPassword;
import jakarta.validation.constraints.NotBlank;

// Completes a login attempt that was interrupted by a mandatory password change
// (fresh account or admin-mediated reset) - proves the temp password, then swaps it.
public record ForceChangePasswordRequest(
    @NotBlank String identifier,
    @NotBlank String currentPassword,
    @NotBlank @StrongPassword String newPassword
) {}
