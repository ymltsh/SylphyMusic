package com.ryanheise.audioservice;

/**
 * The notification is a projection of the ONE MediaSession, not a second
 * position timer. It must be rebuilt on semantic state changes (especially
 * BUFFERING -> PLAYING), but not on every correctly extrapolated position tick.
 * Pure Java so it can be regression-tested without Android/Flutter runtime.
 */
public final class MediaNotificationRefreshPolicy {
    private static final long SEEK_DRIFT_MS = 1500;

    private MediaNotificationRefreshPolicy() {}

    public static boolean requiresRefresh(
            int oldState,
            int newState,
            int playingState,
            boolean hasPreviousAnchor,
            float oldSpeed,
            float speed,
            long oldPositionMs,
            long oldUpdateTimeMs,
            long positionMs,
            long updateTimeMs) {
        if (oldState != newState) return true;
        if (!hasPreviousAnchor) return false;
        boolean wasMoving = oldState == playingState && oldSpeed > 0f;
        boolean moving = newState == playingState && speed > 0f;
        if (wasMoving != moving || Float.compare(oldSpeed, speed) != 0) return true;
        long elapsed = Math.max(0, updateTimeMs - oldUpdateTimeMs);
        double projected = oldPositionMs + (double) elapsed * oldSpeed;
        return Math.abs(positionMs - projected) > SEEK_DRIFT_MS;
    }
}
