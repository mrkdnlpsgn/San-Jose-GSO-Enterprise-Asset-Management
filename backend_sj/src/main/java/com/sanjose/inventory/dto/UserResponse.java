package com.sanjose.inventory.dto;

import lombok.Data;
import lombok.Builder;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UserResponse {
    private Long id;
    private String username;
    private String email;
    private String fullName;
    private String role;
    private Long officeId;
    private String officeName;
    private Long personnelId;
    private String personnelName;
    private int assetCount; // assets this account is accountable for or currently using
    private Boolean isActive;
}
