/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2011 Erwan Velu - All Rights Reserved
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
 * -----------------------------------------------------------------------
 */

#include "hdt-common.h"
#include "hdt-dump.h"
#include "hdt-util.h"

ZZJSON_CONFIG *config;
ZZJSON **item;

static void show_partition_information(struct driveinfo *drive_info,
                                       struct part_entry *ptab,
                                       int partition_offset,
                                       int nb_partitions_seen) {
    char size[11] = {0};
    char bootloader_name[9] = {0};
    char ostype[64]={0};
    char *parttype;
    unsigned int start, end;
    char bootable[6] = {0};

    int i = nb_partitions_seen;
    start = partition_offset;
    end = start + ptab->length - 1;

    if (ptab->length > 0)
        sectors_to_size(ptab->length, size);

    get_label(ptab->ostype, &parttype);
    get_bootloader_string(drive_info, ptab, bootloader_name, 9);
    if (ptab->active_flag == 0x80)
    	snprintf(bootable,sizeof(bootable),"%s","true");
    else
	snprintf(bootable,sizeof(bootable),"%s","false");

    snprintf(ostype,sizeof(ostype),"%02X",ptab->ostype);

    APPEND_ARRAY
	    add_ai("partition->number",i)
	    add_ai("partition->sector_start",start)
	    add_ai("partition->sector_end",end)
	    add_as("partition->size",size)
	    add_as("partition->type",parttype)
	    add_as("partition->os_type",ostype)
	    add_as("partition->boot_flag",bootable)
    END_OF_APPEND;
    free(parttype);
}



void show_disk(struct s_hardware *hardware, ZZJSON_CONFIG *conf, ZZJSON **it, int drive) {
	config=conf;
	item=it;
	int i = drive - 0x80;
	struct driveinfo *d = &hardware->disk_info[i];
	char mbr_name[50]={0};
	char disk_size[11]={0};

	get_mbr_string(hardware->mbr_ids[i], &mbr_name,sizeof(mbr_name));
	if ((int)d->edd_params.sectors > 0)
		sectors_to_size((int)d->edd_params.sectors, disk_size);

	char disk[5]={0};
	char edd_version[5]={0};
	snprintf(disk,sizeof(disk),"0x%X",d->disk);
	snprintf(edd_version,sizeof(edd_version),"%X",d->edd_version);
	zzjson_print(config, *item);
	zzjson_free(config, *item);

	CREATE_ARRAY
		add_as("disk->number",disk) 
		add_ai("disk->cylinders",d->legacy_max_cylinder +1) 
		add_ai("disk->heads",d->legacy_max_head +1)
		add_ai("disk->sectors_per_track",d->legacy_sectors_per_track)
		add_as("disk->edd_version",edd_version)
		add_as("disk->size",disk_size)
		add_ai("disk->bytes_per_sector",(int)d->edd_params.bytes_per_sector)
		add_ai("disk->sectors_per_track",(int)d->edd_params.sectors_per_track)
		add_as("disk->host_bus",remove_spaces((char *)d->edd_params.host_bus_type))
		add_as("disk->interface_type",remove_spaces((char *)d->edd_params.interface_type))
		add_as("disk->mbr_name",mbr_name)
		add_ai("disk->mbr_id",hardware->mbr_ids[i])
	END_OF_ARRAY;

	if (parse_partition_table(d, &show_partition_information)) {
	        if (errno_disk) { 
			APPEND_ARRAY
				add_as("disk->error", "IO Error")
			END_OF_APPEND;
		} else  {
			APPEND_ARRAY
				add_as("disk->error", "Unrecognized Partition Layout")
			END_OF_APPEND;
		}
	}
}

void dump_disks(struct s_hardware *hardware, ZZJSON_CONFIG *config, ZZJSON **item) {
	bool found=false;

 	if (hardware->disks_count > 0)  
	    for (int drive = 0x80; drive < 0xff; drive++) {
	        if (hardware->disk_info[drive - 0x80].cbios) {
			if (found==false) {
				CREATE_NEW_OBJECT;
				add_b("disks->is_valid",true);
       				found=true;
			}
			show_disk(hardware, config, item, drive);
		}
	}

	if (found==false) {
		CREATE_NEW_OBJECT;
		add_b("disks->is_valid",false);
	}
	FLUSH_OBJECT;
	to_cpio("disks");
}
