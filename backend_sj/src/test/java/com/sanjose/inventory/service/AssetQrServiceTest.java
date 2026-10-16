package com.sanjose.inventory.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.mock;

class AssetQrServiceTest {

    private AssetQrService service;

    @BeforeEach
    void setUp() {
        service = new AssetQrService(mock(JdbcTemplate.class), "test-secret");
    }

    private AssetQrService.Status scan(String code, String propertyNumber, String storedHash) {
        return service.check(service.parse(code), propertyNumber, storedHash);
    }

    @Test
    void hashIsSha256HexAndNeverRepeats() {
        String a = service.issueHash(5L, "COA-2026-001");
        String b = service.issueHash(5L, "COA-2026-001");
        assertEquals(64, a.length());
        assertNotEquals(a, b);
    }

    @Test
    void printedStickerVerifies() {
        String hash = service.issueHash(5L, "COA-2026-001");
        String code = AssetQrService.payload(5L, "COA-2026-001", hash);
        assertEquals("asset:5:COA-2026-001:" + hash.substring(0, 16), code);
        assertEquals(AssetQrService.Status.VERIFIED, scan(code, "COA-2026-001", hash));
    }

    @Test
    void editedOrMadeUpStickerFails() {
        String hash = service.issueHash(5L, "COA-2026-001");
        String tag = hash.substring(0, 16);
        // property number changed on the sticker
        assertEquals(AssetQrService.Status.INVALID, scan("asset:5:COA-2026-999:" + tag, "COA-2026-001", hash));
        // guessed tag
        assertEquals(AssetQrService.Status.INVALID, scan("asset:5:COA-2026-001:0123456789abcdef", "COA-2026-001", hash));
    }

    @Test
    void reissuedHashRetiresOldSticker() {
        String oldHash = service.issueHash(5L, "COA-2026-001");
        String oldSticker = AssetQrService.payload(5L, "COA-2026-001", oldHash);
        String newHash = service.issueHash(5L, "COA-2026-001");
        assertEquals(AssetQrService.Status.INVALID, scan(oldSticker, "COA-2026-001", newHash));
    }

    @Test
    void oldUnsignedStickerIsReportedAsUnsigned() {
        String hash = service.issueHash(5L, "COA-2026-001");
        assertEquals(AssetQrService.Status.UNSIGNED, scan("asset:5:COA-2026-001", "COA-2026-001", hash));
    }

    @Test
    void propertyNumberMayContainColons() {
        AssetQrService.ParsedCode p = service.parse("asset:7:2026-07:H78JD80:0123456789abcdef");
        assertEquals(7L, p.assetId());
        assertEquals("2026-07:H78JD80", p.propertyNumber());
        assertEquals("0123456789abcdef", p.tag());
    }

    @Test
    void nonAssetTextIsNotParsed() {
        assertNull(service.parse("COA-2026-001"));
        assertNull(service.parse("asset:abc:COA"));
        assertNull(service.parse("ict-inv:5:abcdef"));
    }
}
