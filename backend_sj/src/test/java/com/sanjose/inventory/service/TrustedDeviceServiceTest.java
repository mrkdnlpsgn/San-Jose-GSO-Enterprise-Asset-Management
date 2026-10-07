package com.sanjose.inventory.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class TrustedDeviceServiceTest {

    private JdbcTemplate jdbc;
    private TrustedDeviceService service;

    @BeforeEach
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        service = new TrustedDeviceService(jdbc, "test-secret");
    }

    private void user(String username, long id, int tokenVersion) {
        when(jdbc.queryForMap(anyString(), eq(username)))
            .thenReturn(Map.of("user_id", id, "token_version", tokenVersion));
    }

    @Test
    void rememberedAccountIsTrusted() {
        user("ana", 5, 2);
        String cookie = service.remember("ana", null);
        assertTrue(service.isTrusted(5, 2, cookie));
    }

    @Test
    void otherAccountOnTheSameBrowserIsNotTrusted() {
        user("ana", 5, 2);
        String cookie = service.remember("ana", null);
        assertFalse(service.isTrusted(6, 2, cookie));
    }

    @Test
    void passwordChangeOrForgetRevokes() {
        user("ana", 5, 2);
        String cookie = service.remember("ana", null);
        assertFalse(service.isTrusted(5, 3, cookie)); // token_version went up
    }

    @Test
    void tamperedOrForgedTokensAreRejected() {
        user("ana", 5, 2);
        String cookie = service.remember("ana", null);
        String otherUser = cookie.replaceFirst("^5\\.", "6.");                    // edit the user id
        assertFalse(service.isTrusted(6, 2, otherUser));
        String farFuture = "5.2.99999999999." + cookie.substring(cookie.lastIndexOf('.') + 1);
        assertFalse(service.isTrusted(5, 2, farFuture));                          // edit the expiry
        assertFalse(service.isTrusted(5, 2, "5.2.99999999999.not-a-signature"));
        TrustedDeviceService otherServer = new TrustedDeviceService(jdbc, "another-secret");
        assertFalse(otherServer.isTrusted(5, 2, cookie));                         // different secret
    }

    @Test
    void expiredTokenIsRejected() {
        // a correctly signed token whose expiry is in the past
        user("ana", 5, 2);
        String fresh = service.remember("ana", null);
        String sig = fresh.substring(fresh.lastIndexOf('.') + 1);
        assertFalse(service.isTrusted(5, 2, "5.2.1." + sig));
    }

    @Test
    void severalAccountsShareOneBrowserCookie() {
        user("ana", 5, 2);
        user("ben", 7, 0);
        String cookie = service.remember("ben", service.remember("ana", null));
        assertTrue(service.isTrusted(5, 2, cookie));
        assertTrue(service.isTrusted(7, 0, cookie));
        // remembering ana again replaces her old token instead of adding a second one
        String again = service.remember("ana", cookie);
        assertEquals(2, again.split("\\|").length);
    }

    @Test
    void emptyOrGarbageCookieIsNotTrusted() {
        assertFalse(service.isTrusted(5, 2, null));
        assertFalse(service.isTrusted(5, 2, ""));
        assertFalse(service.isTrusted(5, 2, "|||garbage|.|"));
    }
}
