/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2006-2007 Erwan Velu - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

/*
 * pci.c
 *
 * A module to extract pci informations
 */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <console.h>
#include <sys/pci.h>
#include <com32.h>
#include <stdbool.h>
#include <ctype.h>
#include <syslinux/zio.h>
#include <dprintf.h>

#define MAX_LINE 512

/* removing any \n found in a string */
static void remove_eol(char *string)
{
    int j = strlen(string);
    int i = 0;
    for (i = 0; i < j; i++)
	if (string[i] == '\n')
	    string[i] = 0;
}

/* converting a hexa string into its numerical value */
static int hex_to_int(char *hexa)
{
    return strtoul(hexa, NULL, 16);
}

/* Try to match any pci device to the appropriate kernel module */
/* it uses the modules.pcimap from the boot device */
int get_module_name_from_pcimap(struct pci_domain *domain,
				char *modules_pcimap_path)
{
  char line[MAX_LINE];
  char module_name[21]; // the module name field is 21 char long
  char delims[]=" ";    // colums are separated by spaces
  char vendor_id[16];
  char product_id[16];
  char sub_vendor_id[16];
  char sub_product_id[16];
  FILE *f;
  struct pci_device *dev=NULL;

  /* Intializing the linux_kernel_module for each pci device to "unknown" */
  /* adding a dev_info member if needed */
  for_each_pci_func(dev, domain) {
    /* initialize the dev_info structure if it doesn't exist yet. */
    if (! dev->dev_info) {
      dev->dev_info = zalloc(sizeof *dev->dev_info);
      if (!dev->dev_info)
	return -1;
    }
    for (int i=0;i<MAX_KERNEL_MODULES_PER_PCI_DEVICE;i++) {
     if (strlen(dev->dev_info->linux_kernel_module[i])==0)
       strlcpy(dev->dev_info->linux_kernel_module[i], "unknown",7);
    }
  }

  /* Opening the modules.pcimap (of a linux kernel) from the boot device */
  f=zfopen(modules_pcimap_path, "r");
  if (!f)
    return -ENOMODULESPCIMAP;

  strcpy(vendor_id,"0000");
  strcpy(product_id,"0000");
  strcpy(sub_product_id,"0000");
  strcpy(sub_vendor_id,"0000");

  /* for each line we found in the modules.pcimap */
  while ( fgets(line, sizeof line, f) ) {
    /* skipping unecessary lines */
    if ((line[0] == '#') || (line[0] == ' ') || (line[0] == 10))
        continue;

    char *result = NULL;
    int field=0;

    /* looking for the next field */
    result = strtok(line, delims);
    while( result != NULL ) {
       /* if the column is larger than 1 char */
       /* multiple spaces generates some empty fields */
       if (strlen(result)>1) {
	 switch (field) {
	 /* About case 0, the kernel module name is featuring '_' or '-' 
	  * in the module name whereas modules.alias is only using '_'.
	  * To avoid kernel modules duplication, let's rename all '-' in '_' 
	  * to match what modules.alias provides */
	 case 0:chrreplace(result,'-','_');strcpy(module_name,result); break;
	 case 1:strcpy(vendor_id,result); break;
	 case 2:strcpy(product_id,result); break;
	 case 3:strcpy(sub_vendor_id,result); break;
	 case 4:strcpy(sub_product_id,result); break;
	 }
	 field++;
       }
       /* Searching the next field */
       result = strtok( NULL, delims );
   }
    int int_vendor_id=hex_to_int(vendor_id);
    int int_sub_vendor_id=hex_to_int(sub_vendor_id);
    int int_product_id=hex_to_int(product_id);
    int int_sub_product_id=hex_to_int(sub_product_id);
    /* if a pci_device matches an entry, fill the linux_kernel_module with
       the appropriate kernel module */
    for_each_pci_func(dev, domain) {
      if (int_vendor_id == dev->vendor &&
	  int_product_id == dev->product &&
	  (int_sub_product_id & dev->sub_product)
	  == dev->sub_product &&
	  (int_sub_vendor_id & dev->sub_vendor)
	  == dev->sub_vendor) {
	      bool found=false;

	      /* Scan all known kernel modules for this pci device */
	      for (int i=0; i<dev->dev_info->linux_kernel_module_count; i++) {

       	      /* Try to detect if we already knew the same kernel module*/
	       if (strstr(dev->dev_info->linux_kernel_module[i], module_name)) {
		      found=true;
		      break;
	       }
	      }
	      /* If we don't have this kernel module, let's add it */
	      if (!found) {
		strcpy(dev->dev_info->linux_kernel_module[dev->dev_info->linux_kernel_module_count], module_name);
		dev->dev_info->linux_kernel_module_count++;
	      }
      }
    }
  }
  fclose(f);
  return 0;
}

/* Try to match any pci device to the appropriate class name */
/* it uses the pci.ids from the boot device */
int get_class_name_from_pci_ids(struct pci_domain *domain, char *pciids_path)
{
    char line[MAX_LINE];
    char class_name[PCI_CLASS_NAME_SIZE];
    char sub_class_name[PCI_CLASS_NAME_SIZE];
    char class_id_str[5];
    char sub_class_id_str[5];
    FILE *f;
    struct pci_device *dev;
    bool class_mode = false;

    /* Intializing the vendor/product name for each pci device to "unknown" */
    /* adding a dev_info member if needed */
    for_each_pci_func(dev, domain) {
	/* initialize the dev_info structure if it doesn't exist yet. */
	if (!dev->dev_info) {
	    dev->dev_info = zalloc(sizeof *dev->dev_info);
	    if (!dev->dev_info)
		return -1;
	}
	strlcpy(dev->dev_info->class_name, "unknown", 7);
    }

    /* Opening the pci.ids from the boot device */
    f = zfopen(pciids_path, "r");
    if (!f)
	return -ENOPCIIDS;

    /* for each line we found in the pci.ids */
    while (fgets(line, sizeof line, f)) {
	/* Skipping uncessary lines */
	if ((line[0] == '#') || (line[0] == ' ') || (line[0] == 10))
	    continue;

	/* Until we found a line starting with a 'C', we are not parsing classes */
	if (line[0] == 'C')
	    class_mode = true;
	if (class_mode == false)
	    continue;
	strlcpy(class_name, "unknown", 7);
	/* If the line doesn't start with a tab, it means that's a class name */
	if (line[0] != '\t') {

	    /* ignore the two first char and then copy 2 chars (class id) */
	    strlcpy(class_id_str, &line[2], 2);
	    class_id_str[2] = 0;

	    /* the class name is the next field */
	    strlcpy(class_name, skipspace(strstr(line, " ")),
		    PCI_CLASS_NAME_SIZE - 1);
	    remove_eol(class_name);

	    int int_class_id_str = hex_to_int(class_id_str);
	    /* assign the class_name to any matching pci device */
	    for_each_pci_func(dev, domain) {
		if (int_class_id_str == dev->class[2]) {
		    strlcpy(dev->dev_info->class_name, class_name,
			    PCI_CLASS_NAME_SIZE - 1);
		    /* This value is usually the main category */
		    strlcpy(dev->dev_info->category_name, class_name + 4,
			    PCI_CLASS_NAME_SIZE - 1);
		}
	    }
	    /* if we have a tab + a char, it means this is a sub class name */
	} else if ((line[0] == '\t') && (line[1] != '\t')) {

	    /* the sub class name the second field */
	    strlcpy(sub_class_name, skipspace(strstr(line, " ")),
		    PCI_CLASS_NAME_SIZE - 1);
	    remove_eol(sub_class_name);

	    /* the sub class id is first field */
	    strlcpy(sub_class_id_str, &line[1], 2);
	    sub_class_id_str[2] = 0;

	    int int_class_id_str = hex_to_int(class_id_str);
	    int int_sub_class_id_str = hex_to_int(sub_class_id_str);
	    /* assign the product_name to any matching pci device */
	    for_each_pci_func(dev, domain) {
		if (int_class_id_str == dev->class[2] &&
		    int_sub_class_id_str == dev->class[1])
		    strlcpy(dev->dev_info->class_name, sub_class_name,
			    PCI_CLASS_NAME_SIZE - 1);
	    }

	}
    }
    fclose(f);
    return 0;
}

/* Try to match any pci device to the appropriate vendor and product name */
/* it uses the pci.ids from the boot device */
int get_name_from_pci_ids(struct pci_domain *domain, char *pciids_path)
{
    char line[MAX_LINE];
    char vendor[PCI_VENDOR_NAME_SIZE];
    char vendor_id[5];
    char product[PCI_PRODUCT_NAME_SIZE];
    char product_id[5];
    char sub_product_id[5];
    char sub_vendor_id[5];
    FILE *f;
    struct pci_device *dev;
    bool skip_to_next_vendor = false;
    uint16_t int_vendor_id;
    uint16_t int_product_id;
    uint16_t int_sub_product_id;
    uint16_t int_sub_vendor_id;

    /* Intializing the vendor/product name for each pci device to "unknown" */
    /* adding a dev_info member if needed */
    for_each_pci_func(dev, domain) {
	/* initialize the dev_info structure if it doesn't exist yet. */
	if (!dev->dev_info) {
	    dev->dev_info = zalloc(sizeof *dev->dev_info);
	    if (!dev->dev_info)
		return -1;
	}
	strlcpy(dev->dev_info->vendor_name, "unknown", 7);
	strlcpy(dev->dev_info->product_name, "unknown", 7);
    }

    /* Opening the pci.ids from the boot device */
    f = zfopen(pciids_path, "r");
    if (!f)
	return -ENOPCIIDS;

    strlcpy(vendor_id, "0000", 4);
    strlcpy(product_id, "0000", 4);
    strlcpy(sub_product_id, "0000", 4);
    strlcpy(sub_vendor_id, "0000", 4);

    /* for each line we found in the pci.ids */
    while (fgets(line, sizeof line, f)) {
	/* Skipping uncessary lines */
	if ((line[0] == '#') || (line[0] == ' ') || (line[0] == 'C') ||
	    (line[0] == 10))
	    continue;

	/* If the line doesn't start with a tab, it means that's a vendor id */
	if (line[0] != '\t') {

	    /* the 4 first chars are the vendor_id */
	    strlcpy(vendor_id, line, 4);

	    /* the vendor name is the next field */
	    vendor_id[4] = 0;
	    strlcpy(vendor, skipspace(strstr(line, " ")),
		    PCI_VENDOR_NAME_SIZE - 1);

	    remove_eol(vendor);
	    /* init product_id, sub_product and sub_vendor */
	    strlcpy(product_id, "0000", 4);
	    strlcpy(sub_product_id, "0000", 4);
	    strlcpy(sub_vendor_id, "0000", 4);

	    /* Unless we found a matching device, we have to skip to the next vendor */
	    skip_to_next_vendor = true;

	    int_vendor_id = hex_to_int(vendor_id);
	    /* Iterate in all pci devices to find a matching vendor */
	    for_each_pci_func(dev, domain) {
		/* if one device that match this vendor */
		if (int_vendor_id == dev->vendor) {
		    /* copy the vendor name for this device */
		    strlcpy(dev->dev_info->vendor_name, vendor,
			    PCI_VENDOR_NAME_SIZE - 1);
		    /* Some pci devices match this vendor, so we have to found them */
		    skip_to_next_vendor = false;
		    /* Let's loop on the other devices as some may have the same vendor */
		}
	    }
	    /* if we have a tab + a char, it means this is a product id
	     * but we only look at it if we own some pci devices of the current vendor*/
	} else if ((line[0] == '\t') && (line[1] != '\t')
		   && (skip_to_next_vendor == false)) {

	    /* the product name the second field */
	    strlcpy(product, skipspace(strstr(line, " ")),
		    PCI_PRODUCT_NAME_SIZE - 1);
	    remove_eol(product);

	    /* the product id is first field */
	    strlcpy(product_id, &line[1], 4);
	    product_id[4] = 0;

	    /* init sub_product and sub_vendor */
	    strlcpy(sub_product_id, "0000", 4);
	    strlcpy(sub_vendor_id, "0000", 4);

	    int_vendor_id = hex_to_int(vendor_id);
	    int_product_id = hex_to_int(product_id);
	    /* assign the product_name to any matching pci device */
	    for_each_pci_func(dev, domain) {
		if (int_vendor_id == dev->vendor &&
		    int_product_id == dev->product) {
		    strlcpy(dev->dev_info->vendor_name, vendor,
			    PCI_VENDOR_NAME_SIZE - 1);
		    strlcpy(dev->dev_info->product_name, product,
			    PCI_PRODUCT_NAME_SIZE - 1);
		}
	    }

	    /* if we have two tabs, it means this is a sub product
	     * but we only look at it if we own some pci devices of the current vendor*/
	} else if ((line[0] == '\t') && (line[1] == '\t')
		   && (skip_to_next_vendor == false)) {

	    /* the product name is last field */
	    strlcpy(product, skipspace(strstr(line, " ")),
		    PCI_PRODUCT_NAME_SIZE - 1);
	    strlcpy(product, skipspace(strstr(product, " ")),
		    PCI_PRODUCT_NAME_SIZE - 1);
	    remove_eol(product);

	    /* the sub_vendor id is first field */
	    strlcpy(sub_vendor_id, &line[2], 4);
	    sub_vendor_id[4] = 0;

	    /* the sub_vendor id is second field */
	    strlcpy(sub_product_id, &line[7], 4);
	    sub_product_id[4] = 0;

	    int_vendor_id = hex_to_int(vendor_id);
	    int_sub_vendor_id = hex_to_int(sub_vendor_id);
	    int_product_id = hex_to_int(product_id);
	    int_sub_product_id = hex_to_int(sub_product_id);
	    /* assign the product_name to any matching pci device */
	    for_each_pci_func(dev, domain) {
		if (int_vendor_id == dev->vendor &&
		    int_product_id == dev->product &&
		    int_sub_product_id == dev->sub_product &&
		    int_sub_vendor_id == dev->sub_vendor) {
		    strlcpy(dev->dev_info->vendor_name, vendor,
			    PCI_VENDOR_NAME_SIZE - 1);
		    strlcpy(dev->dev_info->product_name, product,
			    PCI_PRODUCT_NAME_SIZE - 1);
		}
	    }
	}
    }
    fclose(f);
    return 0;
}

/* searching if any pcidevice match our query */
struct match *find_pci_device(const struct pci_domain *domain,
			      struct match *list)
{
    uint32_t did, sid;
    struct match *m;
    const struct pci_device *dev;

    /* for all matches we have to search */
    for (m = list; m; m = m->next) {
	/* for each pci device we know */
	for_each_pci_func(dev, domain) {
	    /* sid & did are the easiest way to compare devices */
	    /* they are made of vendor/product subvendor/subproduct ids */
	    sid = dev->svid_sdid;
	    did = dev->vid_did;
	    /* if the current device match */
	    if (((did ^ m->did) & m->did_mask) == 0 &&
		((sid ^ m->sid) & m->sid_mask) == 0 &&
		dev->revision >= m->rid_min && dev->revision <= m->rid_max) {
		dprintf
		    ("PCI Match: Vendor=%04x Product=%04x Sub_vendor=%04x Sub_Product=%04x Release=%02x\n",
		     dev->vendor, dev->product, dev->sub_vendor,
		     dev->sub_product, dev->revision);
		/* returning the matched pci device */
		return m;
	    }
	}
    }
    return NULL;
}

/* scanning the pci bus to find pci devices */
struct pci_domain *pci_scan(void)
{
    struct pci_domain *domain = NULL;
    struct pci_bus *bus = NULL;
    struct pci_slot *slot = NULL;
    struct pci_device *func = NULL;
    unsigned int nbus, ndev, nfunc, maxfunc;
    uint32_t did, sid, rcid;
    uint8_t hdrtype;
    pciaddr_t a;
    int cfgtype;

    cfgtype = pci_set_config_type(PCI_CFG_AUTO);

    dprintf("PCI configuration type %d\n", cfgtype);

    if (cfgtype == PCI_CFG_NONE)
	return NULL;

    dprintf("Scanning PCI Buses\n");

    for (nbus = 0; nbus < MAX_PCI_BUSES; nbus++) {
	dprintf("Probing bus 0x%02x... \n", nbus);
	bus = NULL;

	for (ndev = 0; ndev < MAX_PCI_DEVICES; ndev++) {
	    maxfunc = 1;	/* Assume a single-function device */
	    slot = NULL;

	    for (nfunc = 0; nfunc < maxfunc; nfunc++) {
		a = pci_mkaddr(nbus, ndev, nfunc, 0);
		did = pci_readl(a);

		if (did == 0xffffffff || did == 0xffff0000 ||
		    did == 0x0000ffff || did == 0x00000000)
		    continue;

		hdrtype = pci_readb(a + 0x0e);

		if (hdrtype & 0x80)
		    maxfunc = MAX_PCI_FUNC;	/* Multifunction device */

		rcid = pci_readl(a + 0x08);
		sid = pci_readl(a + 0x2c);

		if (!domain) {
		    domain = zalloc(sizeof *domain);
		    if (!domain)
			goto bail;
		}
		if (!bus) {
		    bus = zalloc(sizeof *bus);
		    if (!bus)
			goto bail;
		    domain->bus[nbus] = bus;
		}
		if (!slot) {
		    slot = zalloc(sizeof *slot);
		    if (!slot)
			goto bail;
		    bus->slot[ndev] = slot;
		}
		func = zalloc(sizeof *func);
		if (!func)
		    goto bail;

		slot->func[nfunc] = func;

		func->vid_did = did;
		func->svid_sdid = sid;
		func->rid_class = rcid;

		dprintf
		    ("Scanning: BUS %02x DID %08x (%04x:%04x) SID %08x RID %02x\n",
		     nbus, did, did >> 16, (did << 16) >> 16, sid, rcid & 0xff);
	    }
	}
    }

    return domain;

bail:
    free_pci_domain(domain);
    return NULL;
}

/* gathering additional configuration*/
void gather_additional_pci_config(struct pci_domain *domain)
{
    struct pci_device *dev;
    pciaddr_t pci_addr;
    int cfgtype;

    cfgtype = pci_set_config_type(PCI_CFG_AUTO);
    if (cfgtype == PCI_CFG_NONE)
	return;

    for_each_pci_func3(dev, domain, pci_addr) {
	if (!dev->dev_info) {
	    dev->dev_info = zalloc(sizeof *dev->dev_info);
	    if (!dev->dev_info) {
		return;
	    }
	}
	dev->dev_info->irq = pci_readb(pci_addr + 0x3c);
	dev->dev_info->latency = pci_readb(pci_addr + 0x0d);
    }
}

void free_pci_domain(struct pci_domain *domain)
{
    struct pci_bus *bus;
    struct pci_slot *slot;
    struct pci_device *func;
    unsigned int nbus, ndev, nfunc;

    if (domain) {
	for (nbus = 0; nbus < MAX_PCI_BUSES; nbus++) {
	    bus = domain->bus[nbus];
	    if (bus) {
		for (ndev = 0; ndev < MAX_PCI_DEVICES; ndev++) {
		    slot = bus->slot[ndev];
		    if (slot) {
			for (nfunc = 0; nfunc < MAX_PCI_FUNC; nfunc++) {
			    func = slot->func[nfunc];
			    if (func) {
				if (func->dev_info)
				    free(func->dev_info);
				free(func);
			    }
			}
			free(slot);
		    }
		}
		free(bus);
	    }
	}
	free(domain);
    }
}

/* Try to match any pci device to the appropriate kernel module */
/* it uses the modules.alias from the boot device */
int get_module_name_from_alias(struct pci_domain *domain, char *modules_alias_path)
{
  char line[MAX_LINE];
  char module_name[21]; // the module name field is 21 char long
  char delims[]="*";    // colums are separated by spaces
  char vendor_id[16];
  char product_id[16];
  char sub_vendor_id[16];
  char sub_product_id[16];
  FILE *f;
  struct pci_device *dev=NULL;

  /* Intializing the linux_kernel_module for each pci device to "unknown" */
  /* adding a dev_info member if needed */
  for_each_pci_func(dev, domain) {
    /* initialize the dev_info structure if it doesn't exist yet. */
    if (! dev->dev_info) {
      dev->dev_info = zalloc(sizeof *dev->dev_info);
      if (!dev->dev_info)
	return -1;
    }
    for (int i=0;i<MAX_KERNEL_MODULES_PER_PCI_DEVICE;i++) {
     if (strlen(dev->dev_info->linux_kernel_module[i])==0)
       strlcpy(dev->dev_info->linux_kernel_module[i], "unknown",7);
    }
  }

  /* Opening the modules.pcimap (of a linux kernel) from the boot device */
  f=zfopen(modules_alias_path, "r");
  if (!f)
    return -ENOMODULESALIAS;

  /* for each line we found in the modules.pcimap */
  while ( fgets(line, sizeof line, f) ) {
    /* skipping unecessary lines */
    if ((line[0] == '#') || (strstr(line,"alias pci:v")==NULL))
        continue;

    /* Resetting temp buffer*/
    memset(module_name,0,sizeof(module_name));
    memset(vendor_id,0,sizeof(vendor_id));
    memset(sub_vendor_id,0,sizeof(sub_vendor_id));
    memset(product_id,0,sizeof(product_id));
    memset(sub_product_id,0,sizeof(sub_product_id));
    strcpy(vendor_id,"0000");
    strcpy(product_id,"0000");
    /* ffff will be used to match any device as in modules.alias
     * a missing subvendor/product have to be considered as  0xFFFF*/
    strcpy(sub_product_id,"ffff");
    strcpy(sub_vendor_id,"ffff");

    char *result = NULL;
    int field=0;

    /* looking for the next field */
    result = strtok(line+strlen("alias pci:v"), delims);
    while( result != NULL ) {
	if (field==0) {

		/* Searching for the vendor separator*/
		char *temp = strstr(result,"d");
		if (temp != NULL) {
			strlcpy(vendor_id,result,temp-result);
			result+=strlen(vendor_id)+1;
		}

		/* Searching for the product separator*/
		temp = strstr(result,"sv");
		if (temp != NULL) {
			strlcpy(product_id,result,temp-result);
			result+=strlen(product_id)+1;
		}

		/* Searching for the sub vendor separator*/
		temp = strstr(result,"sd");
		if (temp != NULL) {
			strlcpy(sub_vendor_id,result,temp-result);
			result+=strlen(sub_vendor_id)+1;
		}

		/* Searching for the sub product separator*/
		temp = strstr(result,"bc");
		if (temp != NULL) {
			strlcpy(sub_product_id,result,temp-result);
			result+=strlen(sub_product_id)+1;
		}
	/* That's the module name */
	} else if ((strlen(result)>2) &&
			(result[0]==0x20))
		strcpy(module_name,result+1);
		/* We have to replace \n by \0*/
		module_name[strlen(module_name)-1]='\0';
	field++;

	/* Searching the next field */
        result = strtok( NULL, delims );
    }

    /* Now we have extracted informations from the modules.alias
     * Let's compare it with the devices we know*/
    int int_vendor_id=hex_to_int(vendor_id);
    int int_sub_vendor_id=hex_to_int(sub_vendor_id);
    int int_product_id=hex_to_int(product_id);
    int int_sub_product_id=hex_to_int(sub_product_id);
    /* if a pci_device matches an entry, fill the linux_kernel_module with
       the appropriate kernel module */
    for_each_pci_func(dev, domain) {
      if (int_vendor_id == dev->vendor &&
	  int_product_id == dev->product &&
	  (int_sub_product_id & dev->sub_product)
	  == dev->sub_product &&
	  (int_sub_vendor_id & dev->sub_vendor)
	  == dev->sub_vendor) {
	      bool found=false;
	      
	      /* Scan all known kernel modules for this pci device */
	      for (int i=0; i<dev->dev_info->linux_kernel_module_count; i++) {

       	      /* Try to detect if we already knew the same kernel module*/
	       if (strstr(dev->dev_info->linux_kernel_module[i], module_name)) {
		      found=true;
		      break;
	       }
	      }
	      /* If we don't have this kernel module, let's add it */
	      if (!found) {
		strcpy(dev->dev_info->linux_kernel_module[dev->dev_info->linux_kernel_module_count], module_name);
		dev->dev_info->linux_kernel_module_count++;
	      }
      }
    }
  }
  fclose(f);
  return 0;
}
