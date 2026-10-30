package com.sanjose.inventory.dto;

import java.math.BigDecimal;

// One line under a repair on the Repair and Maintenance Card: a part (unit, quantity, unit cost,
// total cost = quantity x unit cost) or labor (just a cost). kind: PART | LABOR.
// id: the saved line (null for a new one), so its photos stay with it when the record is edited.
// additional: a part found needed during the repair, so it has no pre-maintenance photo.
public record MaintenanceItem(Long id, String kind, String particular, String unit, BigDecimal quantity,
                              BigDecimal unitCost, BigDecimal totalCost, Boolean additional) {}
