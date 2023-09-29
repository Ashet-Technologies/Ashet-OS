#ifndef _H_SYSLXOPT_
#define _H_SYSLXOPT_

/* These are the options we can set and their values */
struct sys_options {
    unsigned int sectors;
    unsigned int heads;
    int raid_mode;
    int stupid_mode;
    int reset_adv;
    const char *set_once;
    int update_only;
    const char *directory;
    const char *device;
    unsigned int offset;
    const char *menu_save;
    int force;
    int install_mbr;
    int activate_partition;
    const char *bootsecfile;
};

enum long_only_opt {
    OPT_NONE,
    OPT_RESET_ADV,
    OPT_ONCE,
    OPT_DEVICE,
};

enum syslinux_mode {
    MODE_SYSLINUX,		/* Unmounted filesystem */
    MODE_EXTLINUX,
    MODE_SYSLINUX_DOSWIN,
};

void __attribute__ ((noreturn)) usage(int rv, enum syslinux_mode mode);
void parse_options(int argc, char *argv[], enum syslinux_mode mode);
int modify_adv(void);

extern struct sys_options opt;
extern const struct option long_options[];
extern const char short_options[];

#endif
