package com.sanjose.inventory.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

// Moves working assets from NEW to GOOD to SERVICEABLE as they age (see
// AssetService.ageAllConditions): once at startup, so a deploy catches up straight away, and
// every night after midnight Manila time, when an asset may have passed its anniversary.
@Slf4j
@Service
@RequiredArgsConstructor
public class AssetAgingService {

    private final AssetService assetService;

    @EventListener(ApplicationReadyEvent.class)
    public void onStartup() {
        run();
    }

    @Scheduled(cron = "0 5 0 * * *", zone = "Asia/Manila")
    public void nightly() {
        run();
    }

    private void run() {
        try {
            int changed = assetService.ageAllConditions();
            if (changed > 0) log.info("Updated the condition of {} asset(s) by age", changed);
        } catch (RuntimeException e) {
            log.warn("Updating asset conditions by age failed", e);
        }
    }
}
