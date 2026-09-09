package com.sanjose.inventory.dto;

public record SseEvent(String action, Long id, Object data, String actorUsername) {}
