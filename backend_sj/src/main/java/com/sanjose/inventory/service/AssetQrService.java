package com.sanjose.inventory.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.HexFormat;
import java.util.List;
import java.util.regex.Pattern;

// Signs asset QR stickers so a made-up or edited code can be told apart from one this system printed.
//
// Each asset carries a 64-char hex HMAC-SHA256 (assets.sha256_hash), keyed with a server-only secret
// over "asset:{id}:{propertyNumber}:{nonce}". The sticker holds its first TAG_LENGTH chars:
//   asset:{id}:{propertyNumber}:{tag}
// A scan is genuine only when the tag matches the hash stored for that asset AND the property
// number matches the asset's current one. The hash is stored rather than recomputed, so issuing
// a new one (property number changed, or an admin reissuing a lost sticker) makes every older
// sticker for that asset stop verifying.
@Service
public class AssetQrService {

    private static final Logger log = LoggerFactory.getLogger(AssetQrService.class);

    public static final String PREFIX = "asset:";
    // 16 hex chars = 64 bits: impractical to guess, and keeps the QR small enough to scan with the
    // seal covering its middle.
    public static final int TAG_LENGTH = 16;
    private static final Pattern TAG = Pattern.compile("[0-9a-f]{" + TAG_LENGTH + "}");
    // updated_at is ON UPDATE CURRENT_TIMESTAMP; signing isn't an edit, so it keeps its value.
    private static final String SET_HASH =
        "UPDATE assets SET sha256_hash = ?, updated_at = updated_at WHERE asset_id = ?";

    public enum Status { VERIFIED, UNSIGNED, INVALID, NOT_FOUND }

    // A scanned "asset:..." code split into its parts; tag is null on an unsigned (pre-signing) sticker.
    public record ParsedCode(Long assetId, String propertyNumber, String tag) {}

    private final JdbcTemplate jdbcTemplate;
    private final byte[] key;
    private final SecureRandom random = new SecureRandom();

    public AssetQrService(JdbcTemplate jdbcTemplate, @Value("${jwt.secret}") String secret) {
        this.jdbcTemplate = jdbcTemplate;
        this.key = ("asset-qr:" + secret).getBytes(StandardCharsets.UTF_8);
    }

    // A new hash for this asset. Never derived from client input.
    public String issueHash(Long assetId, String propertyNumber) {
        byte[] nonce = new byte[16];
        random.nextBytes(nonce);
        String message = PREFIX + assetId + ":" + propertyNumber + ":" + HexFormat.of().formatHex(nonce);
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(message.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException("Could not sign the asset QR code", e);
        }
    }

    // The text printed into the QR code. Assets without a hash yet get the old unsigned form.
    public static String payload(Long assetId, String propertyNumber, String sha256Hash) {
        String base = PREFIX + assetId + ":" + propertyNumber;
        return sha256Hash != null && sha256Hash.length() >= TAG_LENGTH
            ? base + ":" + sha256Hash.substring(0, TAG_LENGTH)
            : base;
    }

    // Issues and saves a new hash, retiring any sticker printed before; returns the new hash.
    public String reissue(Long assetId, String propertyNumber) {
        String hash = issueHash(assetId, propertyNumber);
        jdbcTemplate.update(SET_HASH, hash, assetId);
        return hash;
    }

    // Null when the text isn't an asset QR code at all (e.g. a property number typed by hand).
    // The property number sits between the id and the tag, so it may itself contain ':'.
    public ParsedCode parse(String raw) {
        if (raw == null) return null;
        String code = raw.trim();
        if (!code.startsWith(PREFIX)) return null;
        String rest = code.substring(PREFIX.length());
        int cut = rest.indexOf(':');
        if (cut <= 0) return null;
        Long id;
        try {
            id = Long.parseLong(rest.substring(0, cut));
        } catch (NumberFormatException e) {
            return null;
        }
        String tail = rest.substring(cut + 1);
        int last = tail.lastIndexOf(':');
        if (last > 0 && TAG.matcher(tail.substring(last + 1)).matches()) {
            return new ParsedCode(id, tail.substring(0, last), tail.substring(last + 1));
        }
        return new ParsedCode(id, tail, null);
    }

    public Status check(ParsedCode code, String propertyNumber, String storedHash) {
        if (code.tag() == null) return Status.UNSIGNED;
        if (storedHash == null || storedHash.length() < TAG_LENGTH) return Status.INVALID;
        boolean tagMatches = MessageDigest.isEqual(
            code.tag().getBytes(StandardCharsets.UTF_8),
            storedHash.substring(0, TAG_LENGTH).getBytes(StandardCharsets.UTF_8));
        return tagMatches && code.propertyNumber().equals(propertyNumber) ? Status.VERIFIED : Status.INVALID;
    }

    // Gives every asset registered before signing existed its hash, once, at startup.
    @EventListener(ApplicationReadyEvent.class)
    public void backfillMissingHashes() {
        try {
            List<Object[]> rows = jdbcTemplate.query(
                "SELECT asset_id, property_number FROM assets WHERE sha256_hash IS NULL OR sha256_hash = ''",
                (rs, rn) -> new Object[]{ rs.getLong("asset_id"), rs.getString("property_number") });
            if (rows.isEmpty()) return;
            List<Object[]> updates = rows.stream()
                .map(r -> new Object[]{ issueHash((Long) r[0], (String) r[1]), r[0] })
                .toList();
            jdbcTemplate.batchUpdate(SET_HASH, updates);
            log.info("Signed QR codes for {} existing assets", updates.size());
        } catch (Exception e) {
            // Unsigned assets still scan (as "unsigned"), so a failure here must not stop the app.
            log.warn("Could not backfill asset QR hashes: {}", e.getMessage());
        }
    }
}
