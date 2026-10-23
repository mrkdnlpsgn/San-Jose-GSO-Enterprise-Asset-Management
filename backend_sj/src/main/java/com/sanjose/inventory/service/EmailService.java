package com.sanjose.inventory.service;

import jakarta.mail.internet.MimeMessage;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class EmailService {

    private final JavaMailSender mailSender;

    @Value("${mail.from:}")
    private String from;

    @Value("${mail.from-name:San Jose GSO Inventory Management System}")
    private String fromName;

    @Value("${notifications.enabled:false}")
    private boolean notificationsEnabled;

    // Hosts like Render's free tier block outbound SMTP. When set, mail is POSTed over HTTPS
    // to a Google Apps Script web app (mail-relay/Code.gs) that sends it from the Gmail
    // account that deployed the script.
    @Value("${mail.relay.url:}")
    private String relayUrl;

    @Value("${mail.relay.secret:}")
    private String relaySecret;

    private final RestTemplate restTemplate;

    public boolean isEnabled() {
        return notificationsEnabled && from != null && !from.isBlank();
    }

    @Async
    public void send(String to, String subject, String htmlBody) {
        if (!notificationsEnabled) {
            log.debug("Email notifications disabled (notifications.enabled=false), skipping.");
            return;
        }
        if (from == null || from.isBlank()) {
            log.warn("Gmail not configured (mail.from is empty), email not sent.");
            return;
        }
        if (!relayUrl.isBlank()) {
            sendViaRelay(to, subject, htmlBody);
            return;
        }
        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setFrom(from, fromName);
            helper.setTo(to);
            helper.setSubject(subject);
            helper.setText(htmlBody, true);
            mailSender.send(message);
            log.info("Email sent to {}", to);
        } catch (Exception e) {
            log.error("Failed to send email to {}: {}", to, e.getMessage());
        }
    }

    private void sendViaRelay(String to, String subject, String htmlBody) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        Map<String, String> body = Map.of(
            "secret",   relaySecret,
            "to",       to,
            "subject",  subject,
            "html",     htmlBody,
            "fromName", fromName
        );

        try {
            // Apps Script sends the mail while handling the POST, then answers with a 302 to
            // its result page - that redirect is success, not something to follow.
            ResponseEntity<String> response =
                restTemplate.postForEntity(relayUrl.trim(), new HttpEntity<>(body, headers), String.class);
            if (response.getStatusCode().is2xxSuccessful() || response.getStatusCode().is3xxRedirection()) {
                log.info("Email sent to {} (relay)", to);
            } else {
                log.error("Mail relay returned {} for {}", response.getStatusCode(), to);
            }
        } catch (Exception e) {
            log.error("Failed to send email to {} via relay: {}", to, e.getMessage());
        }
    }
}
