package com.sanjose.inventory.controller;

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
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// The newest mobile app release, so the app can offer an update when it opens. Public: the check
// runs before sign-in too.
//
// It comes from the repository's latest GitHub release (the "Release mobile app" workflow
// publishes one per version): the release tag gives the version, which names the APK to download.
// Looked up at most every 15 minutes. No release notes are sent: the update notice on the phone
// is just "Version X is available. You have Y." (the full notes stay on the GitHub release page).
//
// Render env vars still override it when set:
//   MOBILE_LATEST_VERSION   e.g. 1.0.1 - the app asks to update when it's older than this
//   MOBILE_MIN_VERSION      optional; older apps must update before continuing
//   MOBILE_DOWNLOAD_URL     where the APK is downloaded
//   MOBILE_RELEASES_REPO    owner/name of the GitHub repository to read releases from
// With no version from either place, the app never prompts.
@Slf4j
@RestController
@RequestMapping("/api/app")
public class AppVersionController {

    private static final Duration FRESH_FOR = Duration.ofMinutes(15);
    // after a failed lookup, try again sooner (keeping the last good answer meanwhile)
    private static final Duration RETRY_AFTER = Duration.ofMinutes(2);
    private static final Pattern TAG = Pattern.compile("/releases/tag/v([0-9][0-9A-Za-z.+-]*)");

    @Value("${app.mobile.latest-version:${MOBILE_LATEST_VERSION:}}")
    private String latestVersion;

    @Value("${app.mobile.min-version:${MOBILE_MIN_VERSION:}}")
    private String minVersion;

    @Value("${app.mobile.download-url:${MOBILE_DOWNLOAD_URL:}}")
    private String downloadUrl;

    @Value("${app.mobile.releases-repo:${MOBILE_RELEASES_REPO:mrkdnlpsgn/San-Jose-GSO-Enterprise-Asset-Management}}")
    private String releasesRepo;

    private final HttpClient noRedirects = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    private record Release(String version, String downloadUrl) {}
    private volatile Release cached;
    private volatile long nextLookupAt;

    @GetMapping("/version")
    public Map<String, Object> version() {
        Release release = latestRelease();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("latestVersion", firstSet(latestVersion, release == null ? null : release.version()));
        body.put("minVersion", blankToNull(minVersion));
        body.put("downloadUrl", firstSet(downloadUrl, release == null ? null : release.downloadUrl()));
        return body;
    }

    // GitHub's REST API allows only 60 unauthenticated calls an hour per IP, and a host like Render
    // shares its outgoing IPs with many other apps, so the limit is often used up already. The
    // plain web links have no such limit: /releases/latest redirects to /releases/tag/v<version>,
    // and the workflow names every release's APK the same way (APK_NAMES, newest naming first).
    private Release latestRelease() {
        if (blankToNull(releasesRepo) == null || System.currentTimeMillis() < nextLookupAt) return cached;
        synchronized (this) {
            if (System.currentTimeMillis() < nextLookupAt) return cached;
            String base = "https://github.com/" + releasesRepo.trim() + "/releases";
            try {
                HttpResponse<Void> latest = noRedirects.send(get(base + "/latest"), HttpResponse.BodyHandlers.discarding());
                String location = latest.headers().firstValue("Location").orElse("");
                Matcher tag = TAG.matcher(location);
                if (!tag.find()) throw new IllegalStateException("GitHub answered " + latest.statusCode() + " with no release tag");
                String version = tag.group(1);
                String download = base + "/download/v" + version + "/";
                cached = new Release(version, apkUrl(download, version));
                nextLookupAt = System.currentTimeMillis() + FRESH_FOR.toMillis();
            } catch (Exception e) {
                if (e instanceof InterruptedException) Thread.currentThread().interrupt();
                log.warn("Couldn't read the latest mobile release from GitHub: {}", e.getMessage());
                nextLookupAt = System.currentTimeMillis() + RETRY_AFTER.toMillis();
            }
            return cached;
        }
    }

    // Releases up to 1.0.12 were named SJ-Inventory-v<version>.apk; later ones SJ-GSO-EAM-v<version>.apk.
    private static final String[] APK_NAMES = { "SJ-GSO-EAM-v", "SJ-Inventory-v" };

    // The first name that exists on the release (a download link answers with a redirect),
    // or the newest naming when none can be confirmed.
    private String apkUrl(String download, String version) throws Exception {
        for (String name : APK_NAMES) {
            String url = download + name + version + ".apk";
            HttpRequest head = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(5))
                .header("User-Agent", "sjgso-backend").method("HEAD", HttpRequest.BodyPublishers.noBody()).build();
            int status = noRedirects.send(head, HttpResponse.BodyHandlers.discarding()).statusCode();
            if (status >= 200 && status < 400) return url;
        }
        return download + APK_NAMES[0] + version + ".apk";
    }

    private static HttpRequest get(String url) {
        return HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(5))
            .header("User-Agent", "sjgso-backend").GET().build();
    }

    private static String firstSet(String override, String fromRelease) {
        String o = blankToNull(override);
        return o != null ? o : blankToNull(fromRelease);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
