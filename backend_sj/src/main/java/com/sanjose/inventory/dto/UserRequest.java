package com.sanjose.inventory.dto;

import com.sanjose.inventory.validation.StrongPassword;
import lombok.Data;

@Data
public class UserRequest {
    private String username;
    private String email; // optional; required for the user to be able to use forgot-password
    private String fullName;
    private String role;    // ADMIN or STAFF
    private Long officeId; // ignored — offices are assigned on the Personnel module
    private Boolean isActive;

    // used only on create; if null/blank on update, keep existing — @StrongPassword
    // skips null/blank, so this stays valid for the "unchanged" update case
    @StrongPassword
    private String password;

    // create only: generate a random password and email it to `email` instead of using `password`
    private Boolean generatePassword;
}
