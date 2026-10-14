/* Tako's bounded QuickJS embedding. No libc, filesystem or module loader is installed. */
#include "quickjs.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

typedef struct Message { char *text; struct Message *next; } Message;
typedef struct {
    JSRuntime *runtime;
    JSContext *context;
    JSValue promise;
    int started, failed, interrupted, queued;
    int64_t deadline;
    char *error;
    Message *head, *tail;
} Repl;

static int64_t milliseconds(void) {
#ifdef _WIN32
    return (int64_t)GetTickCount64();
#else
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
#endif
}
static char *copy_text(const char *text) {
    size_t length = strlen(text);
    char *copy = malloc(length + 1);
    if (copy) memcpy(copy, text, length + 1);
    return copy;
}
static int interrupt(JSRuntime *runtime, void *opaque) {
    (void)runtime;
    Repl *repl = opaque;
    if (milliseconds() >= repl->deadline) { repl->interrupted = 1; return 1; }
    return 0;
}
static void remember_error(Repl *repl) {
    JSValue error = JS_GetException(repl->context);
    const char *text = JS_ToCString(repl->context, error);
    free(repl->error);
    repl->error = copy_text(repl->interrupted ? "execution_limit" : text ? text : "javascript_error");
    if (text) JS_FreeCString(repl->context, text);
    JS_FreeValue(repl->context, error);
    repl->failed = 1;
}
static JSValue queue_message(JSContext *context, JSValueConst self, int count, JSValueConst *args) {
    (void)self;
    Repl *repl = JS_GetContextOpaque(context);
    if (count != 1 || repl->queued >= 128) return JS_ThrowInternalError(context, "message_limit");
    size_t length = 0;
    const char *text = JS_ToCStringLen(context, &length, args[0]);
    if (!text) return JS_EXCEPTION;
    if (length > 65536) { JS_FreeCString(context, text); return JS_ThrowInternalError(context, "message_too_large"); }
    Message *message = calloc(1, sizeof(Message));
    if (message) message->text = copy_text(text);
    JS_FreeCString(context, text);
    if (!message || !message->text) { free(message); return JS_ThrowOutOfMemory(context); }
    if (repl->tail) repl->tail->next = message; else repl->head = message;
    repl->tail = message;
    repl->queued++;
    return JS_UNDEFINED;
}
EXPORT void *tako_qjs_create(int64_t memory_limit) {
    Repl *repl = calloc(1, sizeof(Repl));
    if (!repl) return NULL;
    repl->runtime = JS_NewRuntime();
    if (!repl->runtime) { free(repl); return NULL; }
    JS_SetMemoryLimit(repl->runtime, (size_t)memory_limit);
    JS_SetMaxStackSize(repl->runtime, 512 * 1024);
    JS_SetCanBlock(repl->runtime, 0);
    repl->context = JS_NewContext(repl->runtime);
    if (!repl->context) { JS_FreeRuntime(repl->runtime); free(repl); return NULL; }
    JS_SetContextOpaque(repl->context, repl);
    JS_SetInterruptHandler(repl->runtime, interrupt, repl);
    repl->promise = JS_UNDEFINED;
    JSValue global = JS_GetGlobalObject(repl->context);
    JS_DefinePropertyValueStr(repl->context, global, "__takoQueue",
        JS_NewCFunction(repl->context, queue_message, "__takoQueue", 1), 0);
    JS_FreeValue(repl->context, global);
    return repl;
}
/* Trusted bootstrap/response evaluation, still bounded against modified JS globals. */
EXPORT int tako_qjs_eval(void *opaque, const char *source, int budget_ms) {
    Repl *repl = opaque;
    repl->interrupted = 0;
    repl->deadline = milliseconds() + budget_ms;
    JSValue value = JS_Eval(repl->context, source, strlen(source), "tako", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(value)) { remember_error(repl); return 0; }
    JS_FreeValue(repl->context, value);
    return 1;
}
EXPORT int tako_qjs_begin(void *opaque, const char *source, int budget_ms) {
    Repl *repl = opaque;
    free(repl->error); repl->error = NULL;
    repl->failed = 0; repl->interrupted = 0; repl->started = 1;
    JS_FreeValue(repl->context, repl->promise);
    repl->deadline = milliseconds() + budget_ms;
    repl->promise = JS_Eval(repl->context, source, strlen(source), "operation",
        JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_ASYNC);
    if (JS_IsException(repl->promise)) { repl->promise = JS_UNDEFINED; remember_error(repl); return 0; }
    return 1;
}
/* Returns JSON status. At most max_jobs jobs and budget_ms CPU wall time per poll. */
EXPORT char *tako_qjs_poll(void *opaque, int max_jobs, int budget_ms) {
    Repl *repl = opaque;
    repl->deadline = milliseconds() + budget_ms;
    repl->interrupted = 0;
    for (int i = 0; i < max_jobs && !repl->failed && JS_IsJobPending(repl->runtime); i++) {
        JSContext *context;
        if (JS_ExecutePendingJob(repl->runtime, &context) < 0) { remember_error(repl); break; }
        if (milliseconds() >= repl->deadline) break;
    }
    JSContext *context = repl->context;
    JSValue result = JS_NewObjectProto(context, JS_NULL);
    JSPromiseStateEnum state = repl->failed ? JS_PROMISE_REJECTED : JS_PromiseState(context, repl->promise);
    int done = repl->failed || state != JS_PROMISE_PENDING;
    JS_SetPropertyStr(context, result, "done", JS_NewBool(context, done));
    JS_SetPropertyStr(context, result, "jobs", JS_NewBool(context, JS_IsJobPending(repl->runtime)));
    if (repl->failed) {
        JS_SetPropertyStr(context, result, "error", JS_NewString(context, repl->error ? repl->error : "javascript_error"));
    } else if (done) {
        JSValue value = JS_PromiseResult(context, repl->promise);
        if (state == JS_PROMISE_REJECTED) {
            const char *text = JS_ToCString(context, value);
            JS_SetPropertyStr(context, result, "error", JS_NewString(context, text ? text : "javascript_error"));
            if (text) JS_FreeCString(context, text);
            JS_FreeValue(context, value);
        } else {
            /* QuickJS async global evaluation wraps the expression in { value }. */
            JSValue expression = JS_GetPropertyStr(context, value, "value");
            JS_FreeValue(context, value);
            JS_SetPropertyStr(context, result, "value", expression);
        }
    }
    JSValue json = JS_JSONStringify(context, result, JS_UNDEFINED, JS_UNDEFINED);
    JS_FreeValue(context, result);
    if (JS_IsException(json)) {
        remember_error(repl);
        return copy_text("{\"done\":true,\"error\":\"value_conversion_failed\"}");
    }
    const char *text = JS_ToCString(context, json);
    char *copy = copy_text(text ? text : "{\"done\":true,\"error\":\"value_conversion_failed\"}");
    if (text) JS_FreeCString(context, text);
    JS_FreeValue(context, json);
    return copy;
}
EXPORT char *tako_qjs_take_message(void *opaque) {
    Repl *repl = opaque;
    Message *message = repl->head;
    if (!message) return NULL;
    char *text = message->text;
    repl->head = message->next;
    if (!repl->head) repl->tail = NULL;
    repl->queued--;
    free(message);
    return text;
}
EXPORT void tako_qjs_free(void *pointer) { free(pointer); }
EXPORT void tako_qjs_close(void *opaque) {
    Repl *repl = opaque;
    if (!repl) return;
    while (repl->head) free(tako_qjs_take_message(repl));
    JS_FreeValue(repl->context, repl->promise);
    JS_FreeContext(repl->context);
    JS_FreeRuntime(repl->runtime);
    free(repl->error);
    free(repl);
}
