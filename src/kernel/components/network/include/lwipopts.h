#ifndef ASHET_OS_lwipopts_h
#define ASHET_OS_lwipopts_h

#define NO_SYS 1
#define LWIP_MPU_COMPATIBLE 0
#define LWIP_TCPIP_CORE_LOCKING 0

#define MEM_SIZE 200000 // configure peak memory usage here

#define MEMP_NUM_PBUF 200 // protocol buffers

// limits for number of sockets:
#define MEMP_NUM_RAW_PCB 64
#define MEMP_NUM_UDP_PCB 64
#define MEMP_NUM_TCP_PCB 64
#define MEMP_NUM_TCP_PCB_LISTEN 64

#define LWIP_STATS 0 // disable stats module

// disable sequential APIs
#define LWIP_SOCKET 0
#define LWIP_NETCONN 0

#endif // ASHET_OS_lwipopts_h
