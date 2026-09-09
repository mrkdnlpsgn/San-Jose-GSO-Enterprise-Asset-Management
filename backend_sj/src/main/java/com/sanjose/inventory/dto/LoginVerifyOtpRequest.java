package com.sanjose.inventory.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

// Step 2 of login 2FA: prove receipt of the emailed code to finish issuing a session.
public record LoginVerifyOtpRequest(
    @NotBlank String identifier,
    @NotBlank @Pattern(regexp = "\\d{6}", message = "Code must be 6 digits") String otp
) {}
