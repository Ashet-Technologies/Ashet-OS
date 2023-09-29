#ifndef ISO9660_SUSP_H
#define ISO9660_SUSP_H 1

/* Public functions of susp_rr.c, a reader for SUSP and Rock Ridge information.
*/

/*  Inspect the ISO 9660 filesystem whether it bears the signatures of
    SUSP and Rock Ridge.
    Set the parameters fs->fs_info->do_rr and fs->fs_info->susp_skip.
    To be called at the end of iso_fs_init().

    SUSP demands an SP entry as first entry in the System Use area of
    the first directory record in the root directory.
    Rock Ridge prescribes at the same directory record an ER entry with
    id field content "RRIP_1991A", or "IEEE_P1282", or "IEEE_1282".

    @param fs       The filesystem to inspect
    @param flag     Bitfield for control purposes:
                    bit0= Demand a Rock Ridge ER entry
    @return         0 No valid SUSP signature found.
                    1 Yes, signature of SUSP found. No ER was demanded.
                    2 ER of RRIP 1.10 found.
                    3 ER of RRIP 1.12 found.
*/
int susp_rr_check_signatures(struct fs_info *fs, int flag);


/*  Obtain the payload bytes of all SUSP entries with the given signature.

    @param fs       The filesystem from which to read CE blocks.
                    fs->fs_info->do_rr must be non-zero or else this function
                    will always return 0 (i.e. no payload found).
    @param dir_rec  Memory containing the whole ISO 9660 directory record.
    @param sig      Two characters of SUSP signature. E.g. "NM", "ER", ...
    @param data     Returns allocated memory with the payload.
                    A trailing 0-byte is added for convenience with strings.
                    If data is returned != NULL, then it has to be disposed
                    by free() when it is no longer needed.
    @param len_data Returns the number of valid bytes in *data.
                    Not included in this count is the convenience 0-byte.
    @param flag     Bitfield for control purposes:
                    bit0= NM/SL mode:
                          Skip 5 header bytes rather than 4.
                          End after first matching entry without CONTINUE bit.
                          Return 0x100 | byte[4] (FLAGS) of first entry.
    @return         >0 Success.
                       *data and *len_data are valid.
                       Only in this case, *data is returned != NULL.
                    0  Desired signature not found.
                   -1  Error.
                       Something is wrong with the ISO 9660 or SUSP data in
                       the image.
*/
int susp_rr_get_entries(struct fs_info *fs, char *dir_rec, char *sig,
                        char **data, int *len_data, int flag);


/*  Obtain the Rock Ridge name of a directory record.
    If the found content of NM entries is longer than 255 characters,
    then this function will not return it, but rather indicate an error.

    @param fs       The filesystem from which to read CE blocks.
                    fs->fs_info->do_rr must be non-zero or else this function
                    will always return 0 (i.e. no Rock Ridge name found).
    @param dir_rec  Memory containing the whole ISO 9660 directory record.
    @param name     Returns allocated memory with the name and a trailing
                    0-byte. name might contain any byte values.
                    If name is returned != NULL, then it has to be disposed
                    by free() when it is no longer needed.
    @param len_name Returns the number of valid bytes in *name.
                    Not included in this count is the 0-byte after the name.
    @return         >0 Success.
                       *name and *len_name are valid.
                       Only in this case, *data is returned != NULL.
                    0  No NM entry found. No Rock Ridge name defined.
                   -1  Error.
                       Something is wrong with the ISO 9660 or SUSP data in
                       the image.
*/
int susp_rr_get_nm(struct fs_info *fs, char *dir_rec,
                   char **name, int *len_name);


#endif /* ! ISO9660_SUSP_H */
