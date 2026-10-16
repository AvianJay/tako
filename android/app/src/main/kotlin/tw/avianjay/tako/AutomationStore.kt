package tw.avianjay.tako

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/** Native ingress survives engine/process death; Drift acknowledges after commit. */
class AutomationStore private constructor(context: Context) : SQLiteOpenHelper(context, "automation_ingress.sqlite", null, 1) {
    private var cachedRules: List<JSONObject>? = null
    companion object {
        @Volatile private var shared: AutomationStore? = null
        fun get(context: Context): AutomationStore = shared ?: synchronized(this) {
            shared ?: AutomationStore(context.applicationContext).also { shared = it }
        }
    }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE events(id TEXT PRIMARY KEY,data TEXT NOT NULL)")
        db.execSQL("CREATE TABLE rules(id TEXT PRIMARY KEY,data TEXT NOT NULL)")
        db.execSQL("CREATE TABLE seen(id TEXT PRIMARY KEY,hash TEXT NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}
    @Synchronized fun rules(): List<JSONObject> = cachedRules ?: readableDatabase.rawQuery("SELECT data FROM rules", null).use { c ->
        buildList { while (c.moveToNext()) add(JSONObject(c.getString(0))) }
    }.also { cachedRules = it }
    @Synchronized fun sync(rules: JSONArray) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete("rules", null, null)
            for (i in 0 until rules.length()) {
                val rule = rules.getJSONObject(i)
                db.insertOrThrow("rules", null, ContentValues().apply { put("id", rule.getString("id")); put("data", rule.toString()) })
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction(); cachedRules = null }
    }
    @Synchronized fun put(event: JSONObject): Boolean = writableDatabase.insertWithOnConflict("events", null, ContentValues().apply {
        put("id", event.getString("id")); put("data", event.toString())
    }, SQLiteDatabase.CONFLICT_IGNORE) != -1L
    @Synchronized fun inbox(): String = readableDatabase.rawQuery("SELECT data FROM events ORDER BY rowid LIMIT 200", null).use { c ->
        val result = JSONArray(); while(c.moveToNext()) result.put(JSONObject(c.getString(0))); result.toString()
    }
    @Synchronized fun acknowledge(ids: List<String>) {
        val db=writableDatabase; db.beginTransaction()
        try { ids.forEach { db.delete("events", "id=?", arrayOf(it)) }; db.setTransactionSuccessful() }
        finally { db.endTransaction() }
    }
    @Synchronized fun changed(key: String, value: String): Boolean {
        val hash=MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
        val old=readableDatabase.rawQuery("SELECT hash FROM seen WHERE id=?",arrayOf(key)).use { if(it.moveToFirst()) it.getString(0) else null }
        if(old==hash) return false
        writableDatabase.insertWithOnConflict("seen",null,ContentValues().apply {put("id",key);put("hash",hash)},SQLiteDatabase.CONFLICT_REPLACE)
        writableDatabase.execSQL("DELETE FROM seen WHERE rowid NOT IN (SELECT rowid FROM seen ORDER BY rowid DESC LIMIT 4096)")
        return true
    }
}
