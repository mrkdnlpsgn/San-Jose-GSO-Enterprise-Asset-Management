package com.sanjose.inventory.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

// The newest mobile app release, so the app can offer an update when it opens. Public: the check
// runs before sign-in too. Set on the server (Render env vars) when a new APK is published:
//   MOBILE_LATEST_VERSION   e.g. 1.0.1 — the app asks to update when it's older than this
//   MOBILE_MIN_VERSION      optional; older apps must update before continuing
//   MOBILE_DOWNLOAD_URL     where the APK is downloaded (e.g. a GitHub release asset)
//   MOBILE_RELEASE_NOTES    optional short text shown in the dialog
// With no latest version set, the app never prompts.
@RestController
@RequestMapping("/api/app")
public class AppVersionController {

    @Value("${app.mobile.latest-version:${MOBILE_LATEST_VERSION:}}")
    private String latestVersion;

    @Value("${app.mobile.min-version:${MOBILE_MIN_VERSION:}}")
    private String minVersion;

    @Value("${app.mobile.download-url:${MOBILE_DOWNLOAD_URL:}}")
    private String downloadUrl;

    @Value("${app.mobile.release-notes:${MOBILE_RELEASE_NOTES:}}")
    private String releaseNotes;

    @GetMapping("/version")
    public Map<String, Object> version() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("latestVersion", blankToNull(latestVersion));
        body.put("minVersion", blankToNull(minVersion));
        body.put("downloadUrl", blankToNull(downloadUrl));
        body.put("releaseNotes", blankToNull(releaseNotes));
        return body;
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
