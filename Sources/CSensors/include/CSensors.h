#ifndef CSENSORS_H
#define CSENSORS_H

#include <CoreFoundation/CoreFoundation.h>

// Private IOKit HID event system API (used to read Apple Silicon temperature sensors).
// Declared with CFTypeRef + CF_RETURNS_RETAINED so Swift manages memory automatically.

CFTypeRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator) CF_RETURNS_RETAINED;
int IOHIDEventSystemClientSetMatching(CFTypeRef client, CFDictionaryRef matching);
CFArrayRef IOHIDEventSystemClientCopyServices(CFTypeRef client) CF_RETURNS_RETAINED;
CFTypeRef IOHIDServiceClientCopyProperty(CFTypeRef service, CFStringRef key) CF_RETURNS_RETAINED;
CFTypeRef IOHIDServiceClientCopyEvent(CFTypeRef service, int64_t type, int32_t options, int64_t timestamp) CF_RETURNS_RETAINED;
double IOHIDEventGetFloatValue(CFTypeRef event, int32_t field);


// ---- AppleSMC ----
// Reads temperatures from the SMC (all T* keys on Apple Silicon, TC* on Intel), values in (0, 120). Returns the number of sensors read (0 on failure) and writes average / max in °C.
int hs_smc_cpu_temperature(double *average, double *maximum);

#endif
