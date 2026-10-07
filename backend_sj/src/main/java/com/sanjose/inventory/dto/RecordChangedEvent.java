package com.sanjose.inventory.dto;

// Published (in-process, not over SSE) whenever an asset / maintenance / disposal change is
// broadcast, so other parts of the backend can react after the change commits — see
// AiAutoGenerator. Same channel/action/id as the SSE event; for "CHANGED" the id is an asset id.
public record RecordChangedEvent(String channel, String action, Long id) {}
