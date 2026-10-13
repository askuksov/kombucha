#ifndef CSMC_SMC_PARAM_STRUCT_H
#define CSMC_SMC_PARAM_STRUCT_H

#include <mach/mach.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfoData;

// Layout of the AppleSMC user client's struct method argument.
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

_Static_assert(sizeof(SMCParamStruct) == 80, "SMCParamStruct is 80 bytes");
_Static_assert(offsetof(SMCParamStruct, vers) == 4, "vers");
_Static_assert(offsetof(SMCParamStruct, pLimitData) == 12, "pLimitData");
_Static_assert(offsetof(SMCParamStruct, keyInfo) == 28, "keyInfo");
_Static_assert(offsetof(SMCParamStruct, result) == 40, "result");
_Static_assert(offsetof(SMCParamStruct, status) == 41, "status");
_Static_assert(offsetof(SMCParamStruct, data8) == 42, "data8");
_Static_assert(offsetof(SMCParamStruct, data32) == 44, "data32");
_Static_assert(offsetof(SMCParamStruct, bytes) == 48, "bytes");

// mach_task_self_ is a mutable C global that Swift 6 refuses to read directly.
static inline mach_port_t csmc_task_self(void) {
    return mach_task_self();
}

#endif
