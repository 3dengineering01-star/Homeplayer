# MainActivity.keepControls reads and restores this field by name.
-keepclassmembers class com.ryanheise.audioservice.AudioService {
    private static *** listener;
}
