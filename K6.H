/*
 *  K6INIT Helper Header
 */

#include <stdio.h>
#include <dos.h>

#include "vesa_vbe.h"

#ifndef __K6_H
#define __K6_H

typedef struct
{
    unsigned long stepping : 4, model : 4, family : 4, type : 2;
} cpuidProcessorType;

// k6.asm exports

extern void k6_getCPUIdentifier(char _far *cpuidString);
extern cpuidProcessorType k6_getCPUProcessorType(void);

extern unsigned short k6_getVBEInfoBlock(vbeInfo _far *vbeInfoBlockPtr);
extern unsigned short k6_getVBEModeInfo(unsigned short videoMode, 
                                        vbeModeInfo _far *vbeModeInfoPtr);

// k6init functionality

int checkAuthenticAMD(void);
int checkSupportedCPU(void);

// VESA LFB functionality

int findLFBs(void);

#endif