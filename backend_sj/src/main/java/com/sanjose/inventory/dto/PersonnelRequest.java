package com.sanjose.inventory.dto;

import lombok.Data;

@Data
public class PersonnelRequest {
    private String fullName;
    private String position;
    private Long officeId;
    private String contactInfo;
}
