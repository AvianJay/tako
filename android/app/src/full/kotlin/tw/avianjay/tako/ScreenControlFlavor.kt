package tw.avianjay.tako

/** GitHub Releases / F-Droid build: screen control through the service. */
object ScreenControlFlavor {
    const val SUPPORTED = true

    fun backend(): ScreenBackend? = TakoAccessibilityService.instance?.reader
}
