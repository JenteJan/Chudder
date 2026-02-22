package nl.jknaapen.fladder.api

/**
 * SyncPlay command type sent from Flutter. Used for overlay and state.
 */
enum class SyncPlayCommandType {
    NONE,
    PAUSE,
    UNPAUSE,
    SEEK,
    STOP;

    companion object {
        fun fromString(value: String?): SyncPlayCommandType =
            when (value?.lowercase()) {
                "pause" -> PAUSE
                "unpause" -> UNPAUSE
                "seek" -> SEEK
                "stop" -> STOP
                else -> NONE
            }
    }
}

/**
 * Wrapper for SyncPlay command state (processing + command type).
 */
data class SyncPlayCommandState(
    val processing: Boolean,
    val commandType: SyncPlayCommandType
)
