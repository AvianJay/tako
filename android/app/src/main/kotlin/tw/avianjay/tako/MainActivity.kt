package tw.avianjay.tako

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var deviceTools: AndroidDeviceApi? = null
    private var permissions: PermissionBroker? = null
    private var screen: ScreenApiHost? = null
    private var notifications: NotificationApiHost? = null
    private var shell: ShellApiHost? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Flutter's first frame repeats the splash mark in place, so cut
            // over without the system fade, which would show both at once.
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        deviceTools = AndroidDeviceApi(this)
        DeviceApi.setUp(messenger, deviceTools)
        val broker = PermissionBroker(this)
        permissions = broker
        screen = ScreenApiHost(this).also { ScreenApi.setUp(messenger, it) }
        notifications = NotificationApiHost(this, broker).also { NotificationApi.setUp(messenger, it) }
        shell = ShellApiHost(this, broker).also { ShellApi.setUp(messenger, it) }
        val events = ControlEvents(messenger)
        ControlSignals.listener = object : ControlSignals.Listener {
            override fun stopRequested() = events.stopRequested {}
            override fun statusChanged() = events.statusChanged {}
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        deviceTools?.onPermissionResult(requestCode)
        this.permissions?.onResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        // Without the engine nothing can stop or approve: leave no prompt or
        // "controlling the screen" notification behind.
        ControlSignals.listener = null
        screen?.dispose()
        shell?.dispose()
        notifications?.dispose()
        permissions?.dispose()
        AlertNotifications.clearSession(this)
        deviceTools?.dispose()
        deviceTools = null
        super.onDestroy()
    }
}
