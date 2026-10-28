package com.sanjose.inventory.dto;

import java.math.BigDecimal;

// One line under a repair on the Repair and Maintenance Card: a part (unit, quantity, unit cost,
// total cost = quantity x unit cost) or labor (just a cost). kind: PART | LABOR.
public record MaintenanceItem(String kind, String particular, String unit, BigDecimal quantity,
                              BigDecimal unitCost, BigDecimal totalCost) {}
