package com.sanjose.inventory.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.core.JsonGenerator;
import tools.jackson.databind.SerializationContext;
import tools.jackson.databind.ValueSerializer;
import tools.jackson.databind.module.SimpleModule;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

// Every DATETIME in this app is UTC: the JVM and MySQL run in UTC, so LocalDateTime.now() and
// NOW() both produce UTC clock times. LocalDateTime carries no zone, though, so it used to go
// out as "2026-10-07T05:43:05" and browsers / the mobile app read it as Philippine time —
// every timestamp showed 8 hours early. This writes them as UTC instants ("…05:43:05Z") so
// clients convert to local time correctly. Plain dates (LocalDate) are calendar dates and
// are left alone.
@Configuration
public class JacksonTimeConfig {

    private static final DateTimeFormatter UTC_INSTANT = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'");

    @Bean
    public SimpleModule utcLocalDateTimeModule() {
        SimpleModule module = new SimpleModule("utc-local-date-time");
        module.addSerializer(LocalDateTime.class, new ValueSerializer<LocalDateTime>() {
            @Override
            public void serialize(LocalDateTime value, JsonGenerator gen, SerializationContext ctxt) {
                gen.writeString(value.format(UTC_INSTANT));
            }
        });
        return module;
    }
}
