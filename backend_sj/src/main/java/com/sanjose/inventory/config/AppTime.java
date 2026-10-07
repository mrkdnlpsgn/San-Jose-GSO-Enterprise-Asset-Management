package com.sanjose.inventory.config;

import java.time.LocalDate;
import java.time.ZoneId;

// The server runs in UTC, but calendar dates in this app (maintenance date, inspection date,
// "today" on the dashboard) are Philippine dates. Between midnight and 8 AM Manila time a plain
// LocalDate.now() would still say yesterday.
public final class AppTime {
    public static final ZoneId ZONE = ZoneId.of("Asia/Manila");

    private AppTime() {}

    public static LocalDate today() {
        return LocalDate.now(ZONE);
    }
}
