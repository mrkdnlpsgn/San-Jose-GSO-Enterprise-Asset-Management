package com.sanjose.inventory.dto;

import lombok.Data;

import java.util.List;

@Data
public class PersonnelRequest {
    private String fullName;
    private String position;
    private Long officeId;        // primary office; older clients send only this
    private List<Long> officeIds; // every office to assign (the primary is officeId, else the first)
    private String contactInfo;
}
