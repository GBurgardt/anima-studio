#include "NDIBridge.h"
#include <stdbool.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <limits.h>
// NDI public C ABI, video v2. Runtime remains the user's installed NDI Tools.
typedef struct { const char *name, *groups; bool video_clock, audio_clock; } Create;
typedef struct { const char *name, *url; } Source;
typedef struct {
    int width, height, fourcc, rate_n, rate_d;
    float aspect;
    int format;
    int64_t timecode;
    uint8_t *data;
    int stride;
    const char *metadata;
    int64_t timestamp;
} Frame;
typedef struct {
    void *lib, *instance;
    void (*send)(void *, const Frame *);
    void (*destroy)(void *);
    const Source *(*source)(void *);
} Sender;
void *studio_ndi_create(void) {
    Sender *s = calloc(1, sizeof(Sender));
    const char *paths[] = {getenv("ANIMA_NDI_LIBRARY"), "/usr/local/lib/libndi.dylib", "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib", "/Applications/NDI Scan Converter.app/Contents/Frameworks/libndi.dylib"};
    for (int i=0; i<4 && !s->lib; i++) if(paths[i] && paths[i][0]) s->lib=dlopen(paths[i], RTLD_NOW|RTLD_LOCAL);
    if (!s->lib) { free(s); return NULL; }
    bool (*initialize)(void) = dlsym(s->lib, "NDIlib_initialize");
    void *(*create)(const Create *) = dlsym(s->lib, "NDIlib_send_create");
    s->send = dlsym(s->lib, "NDIlib_send_send_video_v2");
    s->destroy = dlsym(s->lib, "NDIlib_send_destroy");
    s->source = dlsym(s->lib, "NDIlib_send_get_source_name");
    if (!initialize || !create || !s->send || !s->destroy || !s->source || !initialize()) {
        dlclose(s->lib); free(s); return NULL;
    }
    Create c = {"Anima Studio Monitor", NULL, false, false};
    s->instance = create(&c);
    if (!s->instance) { dlclose(s->lib); free(s); return NULL; }
    return s;
}
const char *studio_ndi_name(void *sender) {
    Sender *s = sender;
    const Source *source = s->source(s->instance);
    return source ? source->name : NULL;
}
void studio_ndi_send(void *sender, uint8_t *data, int width, int height, int stride) {
    Sender *s = sender;
    Frame f = {0};
    f.width = width; f.height = height;
    f.fourcc = 'B' | ('G'<<8) | ('R'<<16) | ('A'<<24);
    f.rate_n = 30; f.rate_d = 1; f.aspect = (float)width/height;
    f.format = 1; f.timecode = INT64_MAX;
    f.data = data; f.stride = stride;
    // Synchronous send: the pixel buffer remains locked until this returns.
    s->send(s->instance, &f);
}
void studio_ndi_destroy(void *sender) {
    if (!sender) return;
    Sender *s = sender; s->destroy(s->instance); dlclose(s->lib); free(s);
}
