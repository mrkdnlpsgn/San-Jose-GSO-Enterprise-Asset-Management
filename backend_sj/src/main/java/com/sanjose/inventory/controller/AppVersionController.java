package com.sanjose.inventory.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// The newest mobile app release, so the app can offer an update when it opens. Public: the check
// runs before sign-in too.
//
// It comes from the repository's latest GitHub release (the "Release mobile app" workflow
// publishes one per version): the tag gives the version, the .apk asset the download link, and
// the bold bullet titles under "What's new" the short notes. Looked up at most every 15 minutes.
//
// Render env vars still override it when set:
//   MOBILE_LATEST_VERSION   e.g. 1.0.1 - the app asks to update when it's older than this
//   MOBILE_MIN_VERSION      optional; older apps must update before continuing
//   MOBILE_DOWNLOAD_URL     where the APK is downloaded
//   MOBILE_RELEASE_NOTES    optional short text shown in the dialog
//   MOBILE_RELEASES_REPO    owner/name of the GitHub repository to read releases from
// With no version from either place, the app never prompts.
@Slf4j
@RestController
@RequestMapping("/api/app")
public class AppVersionController {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private static final Duration FRESH_FOR = Duration.ofMinutes(15);
    // after a failed lookup, try again sooner (keeping the last good answer meanwhile)
    private static final Duration RETRY_AFTER = Duration.ofMinutes(2);
    private static final Pattern NOTE_TITLE = Pattern.compile("^\\s*[-*]\\s+\\*\\*(.+?)[:.]?\\*\\*", Pattern.MULTILINE);

    @Value("${app.mobile.latest-version:${MOBILE_LATEST_VERSION:}}")
    private String latestVersion;

    @Value("${app.mobile.min-version:${MOBILE_MIN_VERSION:}}")
    private String minVersion;

    @Value("${app.mobile.download-url:${MOBILE_DOWNLOAD_URL:}}")
    private String downloadUrl;

    @Value("${app.mobile.release-notes:${MOBILE_RELEASE_NOTES:}}")
    private String releaseNotes;

    @Value("${app.mobile.releases-repo:${MOBILE_RELEASES_REPO:mrkdnlpsgn/San-Jose-GSO-Enterprise-Asset-Management}}")
    private String releasesRepo;

    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    private record Release(String version, String downloadUrl, String notes) {}
    private volatile Release cached;
    private volatile long nextLookupAt;

    @GetMapping("/version")
    public Map<String, Object> version() {
        Release release = latestRelease();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("latestVersion", firstSet(latestVersion, release == null ? null : release.version()));
        body.put("minVersion", blankToNull(minVersion));
        body.put("downloadUrl", firstSet(downloadUrl, release == null ? null : release.downloadUrl()));
        body.put("releaseNotes", firstSet(releaseNotes, release == null ? null : release.notes()));
        return body;
    }

    private Release latestRelease() {
        if (blankToNull(releasesRepo) == null || System.currentTimeMillis() < nextLookupAt) return cached;
        synchronized (this) {
            if (System.currentTimeMillis() < nextLookupAt) return cached;
            try {
                HttpRequest request = HttpRequest.newBuilder(URI.create("https://api.github.com/repos/" + releasesRepo.trim() + "/releases/latest"))
                    .timeout(Duration.ofSeconds(5))
                    .header("Accept", "application/vnd.github+json")
                    .header("User-Agent", "sjgso-backend")
                    .GET().build();
                HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
                if (response.statusCode() != 200) throw new IllegalStateException("GitHub answered " + response.statusCode());
                cached = parse(OBJECT_MAPPER.readTree(response.body()));
                nextLookupAt = System.currentTimeMillis() + FRESH_FOR.toMillis();
            } catch (Exception e) {
                if (e instanceof InterruptedException) Thread.currentThread().interrupt();
                log.warn("Couldn't read the latest mobile release from GitHub: {}", e.getMessage());
                nextLookupAt = System.currentTimeMillis() + RETRY_AFTER.toMillis();
            }
            return cached;
        }
    }

    private static Release parse(JsonNode json) {
        String tag = json.path("tag_name").asText("");
        String version = tag.startsWith("v") ? tag.substring(1) : tag;
        String apk = null;
        for (JsonNode asset : json.path("assets")) {
            if (asset.path("name").asText("").endsWith(".apk")) { apk = asset.path("browser_download_url").asText(null); break; }
        }
        List<String> titles = new ArrayList<>();
        Matcher m = NOTE_TITLE.matcher(json.path("body").asText(""));
        while (m.find() && titles.size() < 4) titles.add(m.group(1).trim());
        String notes = titles.isEmpty() ? null : String.join(". ", titles) + ".";
        return new Release(blankToNull(version), apk, notes);
    }

    private static String firstSet(String override, String fromRelease) {
        String o = blankToNull(override);
        return o != null ? o : blankToNull(fromRelease);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
