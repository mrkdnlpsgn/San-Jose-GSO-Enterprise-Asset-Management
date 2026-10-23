package com.sanjose.inventory.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class SmsService {

    @Value("${philsms.api-key:}")
    private String apiKey;

    @Value("${philsms.sender-id:PhilSMS}")
    private String senderId;

    @Value("${philsms.url:https://app.philsms.com/api/v3/sms/send}")
    private String apiUrl;

    @Value("${notifications.enabled:false}")
    private boolean notificationsEnabled;

    private final RestTemplate restTemplate;

    @Async
    public void send(String mobileNumber, String message) {
        if (!notificationsEnabled) {
            log.debug("SMS notifications disabled (notifications.enabled=false), skipping.");
            return;
        }
        apiKey = apiKey.trim();
        if (apiKey.isBlank()) {
            log.warn("PhilSMS API key not configured: SMS not sent.");
            return;
        }

        String normalized = normalizePhone(mobileNumber);
        if (normalized == null) {
            log.warn("Invalid phone number format: SMS not sent: {}", mobileNumber);
            return;
        }

        log.debug("PhilSMS API key configured, sending SMS.");

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setAccept(List.of(MediaType.APPLICATION_JSON));
        headers.set("Authorization", "Bearer " + apiKey);

        Map<String, String> body = Map.of(
            "recipient", normalized,
            "sender_id", senderId,
            "type",      "plain",
            "message",   message
        );

        try {
            ResponseEntity<String> response = restTemplate.postForEntity(
                apiUrl,
                new HttpEntity<>(body, headers),
                String.class
            );
            log.info("PhilSMS response [{}]: {}", response.getStatusCode(), response.getBody());
        } catch (Exception e) {
            log.error("Failed to send SMS to {}: {}", normalized, e.getMessage());
        }
    }

    private String normalizePhone(String number) {
        if (number == null || number.isBlank()) return null;
        number = number.replaceAll("[\\s\\-]", "");
        if (number.startsWith("+63")) return "63" + number.substring(3);
        if (number.startsWith("63") && number.length() == 12) return number;
        if (number.startsWith("09") && number.length() == 11) return "63" + number.substring(1);
        if (number.startsWith("9")  && number.length() == 10) return "63" + number;
        return null;
    }
}
