package tw.avianjay.tako

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object AutomationBroker {
    private val main=Handler(Looper.getMainLooper())
    private val clients=mutableMapOf<AutomationEvents,Boolean>()
    private var owner: String?=null
    private val stopped=mutableMapOf<String,String>()
    var openRun: String?=null
    @Synchronized fun attach(events:AutomationEvents,foreground:Boolean) {clients[events]=foreground}
    @Synchronized fun detach(events:AutomationEvents) {clients.remove(events)}
    @Synchronized fun acquire(value:String):Boolean {
        if(owner!=null && owner!=value) {
            if(value=="chat") {stopped[owner!!]="chat";stopClients("chat");changed()}
            return false
        }
        owner=value;stopped.remove(value);return true
    }
    @Synchronized fun release(value:String) {if(owner==value) owner=null;stopped.remove(value)}
    @Synchronized fun interrupted(value:String)=stopped[value]
    @Synchronized fun hasAutomationOwner()=owner?.startsWith("automation:")==true
    @Synchronized fun stopBackground() {owner?.takeIf {it.startsWith("automation:") }?.let {stopped[it]="paused";stopClients("paused")};changed()}
    private fun stopClients(reason:String) {main.post {synchronized(this) {clients.keys.toList()}.forEach {it.stop(reason) {}}}}
    fun changed() {main.post {synchronized(this) {clients.keys.toList()}.forEach {it.changed {}}}}
    fun opened(id:String) {openRun=id;main.post {synchronized(this) {clients.filterValues {it}.keys.toList()}.forEach {it.openRun(id) {result -> if(result.isSuccess && openRun==id) openRun=null}}}}
}

class AutomationApiHost(private val context:Context, val events:AutomationEvents, private val onReady:(()->Unit)?=null):AutomationApi {
    private val store=AutomationStore.get(context)
    private val owners=mutableSetOf<String>()
    init {AutomationBroker.attach(events,context is Activity)}
    override fun ready() {onReady?.invoke()}
    override fun status():String {
        val alarms=context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val manager=context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val open=if(context is Activity) AutomationBroker.openRun else null
        if(context is Activity) AutomationBroker.openRun=null
        return JSONObject().put("exact",Build.VERSION.SDK_INT<31 || alarms.canScheduleExactAlarms())
            .put("canPost",manager.areNotificationsEnabled()).put("notificationTriggers",true).put("openRun",open ?: "").toString()
    }
    override fun requestExactPermission() {
        if(Build.VERSION.SDK_INT>=31 && context is Activity) context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:${context.packageName}")))
    }
    override fun requestNotifications(callback:(Result<Boolean>)->Unit) {
        if(Build.VERSION.SDK_INT<33) {callback(Result.success(true));return}
        if(context is MainActivity) context.requestAutomationNotifications(callback)
        else callback(Result.success(false))
    }
    override fun syncRules(rulesJson:String) {
        val previous=store.rules();val incoming=JSONArray(rulesJson)
        store.sync(incoming)
        previous.forEach { old ->
            val replacement=(0 until incoming.length()).map {incoming.getJSONObject(it)}.firstOrNull {it.optString("id")==old.optString("id")}
            if(replacement==null || !replacement.optBoolean("enabled")) AutomationScheduling.cancel(context,old.optString("id"))
            else if(replacement.toString()!=old.toString()) (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(AutomationScheduling.alarm(context,old.optString("id")))
        }
        store.rules().forEach {AutomationScheduling.schedule(context,it)}
    }
    override fun inbox()=store.inbox()
    override fun acknowledge(ids:List<String>)=store.acknowledge(ids)
    override fun wake(at:Long?) {if(at!=null) AutomationScheduling.drainAt(context,at)}
    override fun notify(runId:String,title:String,body:String,waiting:Boolean)=AutomationScheduling.notify(context,runId,title,body,waiting)
    override fun clearNotification(runId:String) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel("automation:$runId",runId.hashCode())
    }
    override fun acquire(owner:String)=AutomationBroker.acquire(owner).also {if(it) owners.add(owner)}
    override fun release(owner:String) {owners.remove(owner);AutomationBroker.release(owner)}
    override fun interrupted(owner:String)=AutomationBroker.interrupted(owner)
    override fun signalChanged()=AutomationBroker.changed()
    fun dispose() {owners.toList().forEach {AutomationBroker.release(it)};owners.clear();AutomationBroker.detach(events)}
}

object AutomationScheduling {
    private const val CHANNEL="automations"
    fun alarm(context:Context,id:String)=PendingIntent.getBroadcast(context,id.hashCode(),Intent(context,AutomationReceiver::class.java).setAction("automation.schedule").setData(Uri.parse("tako-internal://schedule/$id")).putExtra("ruleId",id),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    fun cancel(context:Context,id:String) {
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(alarm(context,id))
        WorkManager.getInstance(context).cancelAllWorkByTag("automation.rule.$id")
    }
    fun schedule(context:Context,rule:JSONObject) {
        if(!rule.optBoolean("enabled") || rule.isNull("nextAt")) return
        val id=rule.getString("id");val at=rule.getLong("nextAt")
        if(rule.optJSONObject("schedule")?.optBoolean("exact")==true) {
            val alarms=context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if(Build.VERSION.SDK_INT>=31 && !alarms.canScheduleExactAlarms()) return
            try {alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,alarm(context,id))} catch(_:SecurityException) {}
        } else {
            val work=OneTimeWorkRequestBuilder<AutomationWorker>().setInputData(androidx.work.workDataOf("ruleId" to id)).addTag("automation.rule.$id")
                .setInitialDelay((at-System.currentTimeMillis()).coerceAtLeast(0),TimeUnit.MILLISECONDS).build()
            WorkManager.getInstance(context).enqueueUniqueWork("automation.schedule.$id.${rule.optInt("revision")}.$at",ExistingWorkPolicy.KEEP,work)
        }
    }
    fun ingress(context:Context) {
        val work=OneTimeWorkRequestBuilder<AutomationWorker>().setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST).build()
        WorkManager.getInstance(context).enqueueUniqueWork("automation.ingress",ExistingWorkPolicy.KEEP,work)
    }
    fun drainAt(context:Context,at:Long) {
        val prefs=context.getSharedPreferences("automation_wake",0)
        if(prefs.getLong("at",-1)==at) return
        prefs.edit().putLong("at",at).apply()
        val work=OneTimeWorkRequestBuilder<AutomationWorker>().setInputData(androidx.work.workDataOf("wakeAt" to at)).setInitialDelay((at-System.currentTimeMillis()).coerceAtLeast(30_000),TimeUnit.MILLISECONDS).build()
        // APPEND avoids cancelling the worker that is currently checkpointing.
        WorkManager.getInstance(context).enqueueUniqueWork("automation.due",ExistingWorkPolicy.APPEND_OR_REPLACE,work)
    }
    fun scheduleEvent(context:Context,id:String) {
        val rule=AutomationStore.get(context).rules().firstOrNull {it.optString("id")==id} ?: return
        if(!rule.optBoolean("enabled") || rule.isNull("nextAt") || rule.getLong("nextAt")>System.currentTimeMillis()) return
        AutomationStore.get(context).put(JSONObject().put("id","schedule:$id:${rule.optInt("revision")}:${rule.getLong("nextAt")}").put("kind","schedule").put("ruleId",id).put("revision",rule.optInt("revision")))
    }
    fun notification(context:Context,runId:String,title:String,body:String,waiting:Boolean):Notification {
        val manager=context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if(Build.VERSION.SDK_INT>=26) manager.createNotificationChannel(NotificationChannel(CHANNEL,context.getString(R.string.automation_channel),NotificationManager.IMPORTANCE_DEFAULT))
        val intent=Intent(context,MainActivity::class.java).setAction("automation.open").setData(Uri.parse("tako-internal://run/$runId")).putExtra("automationRunId",runId).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        val pending=PendingIntent.getActivity(context,runId.hashCode(),intent,PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder=if(Build.VERSION.SDK_INT>=26) Notification.Builder(context,CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context)
        return builder.setSmallIcon(R.drawable.ic_stat_tako).setContentTitle(title.take(120)).setContentText(body.take(240))
            .setStyle(Notification.BigTextStyle().bigText(body.take(6000))).setAutoCancel(true).setContentIntent(pending)
            .setCategory(if(waiting) Notification.CATEGORY_REMINDER else Notification.CATEGORY_STATUS).build()
    }
    fun notify(context:Context,runId:String,title:String,body:String,waiting:Boolean) {
        try {(context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify("automation:$runId",runId.hashCode(),notification(context,runId,title,body,waiting))}catch(_:SecurityException) {}
    }
}

class AutomationReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        if(intent.action=="automation.schedule") {
            intent.getStringExtra("ruleId")?.let {AutomationScheduling.scheduleEvent(context,it)}
            AutomationScheduling.ingress(context)
        } else {
            if(intent.action==Intent.ACTION_TIME_CHANGED || intent.action==Intent.ACTION_TIMEZONE_CHANGED) {
                AutomationStore.get(context).put(JSONObject().put("id",java.util.UUID.randomUUID().toString()).put("kind","clock"))
            }
            AutomationStore.get(context).rules().forEach {AutomationScheduling.schedule(context,it)}
            AutomationScheduling.ingress(context)
        }
    }
}
