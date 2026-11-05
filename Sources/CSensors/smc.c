#include "CSensors.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

typedef struct { char major, minor, build, reserved[1]; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key; SMCVers vers; SMCPLimit pLimitData; SMCKeyInfo keyInfo;
    char result, status, data8; uint32_t data32; unsigned char bytes[32];
} SMCParam;

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCGetKeyFromIndex = 8, kSMCGetKeyInfo = 9 };

#define MAX_KEYS 512
static io_connect_t gConn = 0;
static int gReady = 0;
static uint32_t gKeys[MAX_KEYS];
static SMCKeyInfo gInfos[MAX_KEYS];
static int gKeyCount = 0;

static uint32_t fourcc(const char *k) { return ((uint32_t)k[0] << 24) | ((uint32_t)k[1] << 16) | ((uint32_t)k[2] << 8) | (uint32_t)k[3]; }

static kern_return_t smc_call(SMCParam *in, SMCParam *out) {
    size_t size = sizeof(SMCParam);
    memset(out, 0, sizeof(SMCParam));
    return IOConnectCallStructMethod(gConn, kSMCHandleYPCEvent, in, sizeof(SMCParam), out, &size);
}

static int read_float(uint32_t key, SMCKeyInfo info, double *value) {
    SMCParam in = {0}, out;
    in.key = key; in.keyInfo = info; in.data8 = kSMCReadKey;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) return 0;
    if (info.dataType == fourcc("flt ") && info.dataSize == 4) {
        float f; memcpy(&f, out.bytes, 4); *value = f; return 1;
    }
    if (info.dataType == fourcc("sp78") && info.dataSize == 2) { // Intel fixed point
        *value = (int16_t)((out.bytes[0] << 8) | out.bytes[1]) / 256.0; return 1;
    }
    return 0;
}

static int setup(void) {
    if (gReady) return gKeyCount > 0;
    gReady = 1;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return 0;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &gConn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) return 0;

    // Number of keys
    SMCParam in = {0}, out;
    in.key = fourcc("#KEY"); in.data8 = kSMCGetKeyInfo;
    if (smc_call(&in, &out) != KERN_SUCCESS) return 0;
    in.keyInfo = out.keyInfo; in.data8 = kSMCReadKey;
    if (smc_call(&in, &out) != KERN_SUCCESS) return 0;
    uint32_t n = ((uint32_t)out.bytes[0] << 24) | ((uint32_t)out.bytes[1] << 16) | ((uint32_t)out.bytes[2] << 8) | out.bytes[3];

    for (uint32_t i = 0; i < n && gKeyCount < MAX_KEYS; i++) {
        memset(&in, 0, sizeof in);
        in.data8 = kSMCGetKeyFromIndex; in.data32 = i;
        if (smc_call(&in, &out) != KERN_SUCCESS) continue;
        uint32_t key = out.key;
        char a = (char)(key >> 24), b = (char)(key >> 16);
#if defined(__arm64__)
        (void)b;
        if (a != 'T') continue;   // Apple Silicon: all temperature keys (same set as Hot)
#else
        if (a != 'T' || b != 'C') continue;                  // Intel CPU sensors
#endif
        memset(&in, 0, sizeof in);
        in.key = key; in.data8 = kSMCGetKeyInfo;
        if (smc_call(&in, &out) != KERN_SUCCESS) continue;
        SMCKeyInfo info = out.keyInfo;
        double v;
        if (!read_float(key, info, &v)) continue;
        gKeys[gKeyCount] = key; gInfos[gKeyCount] = info; gKeyCount++;
    }
    return gKeyCount > 0;
}

int hs_smc_cpu_temperature(double *average, double *maximum) {
    if (!setup()) return 0;
    double sum = 0, mx = 0; int count = 0;
    for (int i = 0; i < gKeyCount; i++) {
        double v;
        if (!read_float(gKeys[i], gInfos[i], &v) || v <= 0 || v >= 120) continue;
        sum += v; if (v > mx) mx = v; count++;
    }
    if (count == 0) return 0;
    if (average) *average = sum / count;
    if (maximum) *maximum = mx;
    return count;
}
