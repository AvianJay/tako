package tw.avianjay.tako

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.FlutterInjector
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

class AutomationWorker(context:Context,parameters:WorkerParameters):CoroutineWorker(context,parameters) {
    private var engine:FlutterEngine?=null
    private var api:AutomationApiHost?=null
    override suspend fun getForegroundInfo()=ForegroundInfo(4200,AutomationScheduling.notification(applicationContext,"worker","Tako",applicationContext.getString(R.string.automation_running),false))
    override suspend fun doWork():Result {
        val wakeAt=inputData.getLong("wakeAt",-1)
        val preferences=applicationContext.getSharedPreferences("automation_wake",0)
        if(wakeAt>=0 && preferences.getLong("at",-1)==wakeAt) preferences.edit().remove("at").apply()
        inputData.getString("ruleId")?.let {AutomationScheduling.scheduleEvent(applicationContext,it)}
        var device:AndroidDeviceApi?=null;var screen:ScreenApiHost?=null;var notifications:NotificationApiHost?=null;var shell:ShellApiHost?=null;var aicore:AicoreApiHost?=null
        var successfullyFinished=false
        val success=try {
            withTimeoutOrNull(540_000) {
                withContext(Dispatchers.Main) {
                    suspendCancellableCoroutine<Boolean> { continuation ->
                        val loader=FlutterInjector.instance().flutterLoader()
                        loader.startInitialization(applicationContext);loader.ensureInitializationComplete(applicationContext,null)
                        val flutter=FlutterEngine(applicationContext);engine=flutter
                        val messenger=flutter.dartExecutor.binaryMessenger
                        val broker=PermissionBroker(applicationContext)
                        device=AndroidDeviceApi(applicationContext).also {DeviceApi.setUp(messenger,it)}
                        screen=ScreenApiHost(applicationContext).also {ScreenApi.setUp(messenger,it)}
                        notifications=NotificationApiHost(applicationContext,broker).also {NotificationApi.setUp(messenger,it)}
                        shell=ShellApiHost(applicationContext,broker).also {ShellApi.setUp(messenger,it)}
                        aicore=AicoreApiHost(messenger)
                        val events=AutomationEvents(messenger)
                        api=AutomationApiHost(applicationContext,events) {
                            events.execute {result -> if(continuation.isActive) {successfullyFinished=result.getOrDefault(false);continuation.resume(successfullyFinished)}}
                        }.also {AutomationApi.setUp(messenger,it)}
                        continuation.invokeOnCancellation {Handler(Looper.getMainLooper()).post {events.stop("system") {}}}
                        flutter.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),"automationMain"))
                    }
                }
            } ?: false
        } catch(_:Exception) {false}
        finally {
            withContext(NonCancellable + Dispatchers.Main) {
                if(!successfullyFinished) {
                    api?.events?.stop("system") {}
                    delay(800)
                }
                api?.dispose();device?.dispose();screen?.dispose();notifications?.dispose();shell?.dispose();aicore?.dispose()
                engine?.destroy();engine=null
            }
        }
        if(AutomationStore.get(applicationContext).inbox()!="[]") {
            val next=androidx.work.OneTimeWorkRequestBuilder<AutomationWorker>().setInitialDelay(30,java.util.concurrent.TimeUnit.SECONDS).build()
            androidx.work.WorkManager.getInstance(applicationContext).enqueue(next)
        }
        return if(success) Result.success() else Result.retry()
    }
}
