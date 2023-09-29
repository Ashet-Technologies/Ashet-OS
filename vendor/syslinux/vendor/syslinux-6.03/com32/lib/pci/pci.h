/*
 * pci/pci.h
 *
 * Common internal header file
 */

#ifndef PCI_PCI_H

#include <sys/pci.h>
#include <sys/cpu.h>

extern enum pci_config_type __pci_cfg_type;
extern uint32_t __pci_read_write_bios(uint32_t call, uint32_t v, pciaddr_t a);

#endif /* PCI_PCI_H */
