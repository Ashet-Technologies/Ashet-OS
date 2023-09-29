#include <stdlib.h>
#include <syslinux/linux.h>
#include <syslinux/loadfile.h>

struct setup_data *setup_data_init(void)
{
    struct setup_data *setup_data;

    setup_data = zalloc(sizeof(*setup_data));
    if (!setup_data)
	return NULL;

    setup_data->prev = setup_data->next = setup_data;
    return setup_data;
}

int setup_data_add(struct setup_data *head, uint32_t type,
		   const void *data, size_t data_len)
{
	struct setup_data *setup_data;

	setup_data = zalloc(sizeof(*setup_data));
	if (!setup_data)
	    return -1;

	setup_data->data     = data;
	setup_data->hdr.len  = data_len;
	setup_data->hdr.type = type;
	setup_data->prev     = head->prev;
	setup_data->next     = head;
	head->prev->next     = setup_data;
	head->prev           = setup_data;

	return 0;
}

int setup_data_load(struct setup_data *head, uint32_t type,
		    const char *filename)
{
	void *data;
	size_t len;

	if (loadfile(filename, &data, &len))
		return -1;

	return setup_data_add(head, type, data, len);
}
