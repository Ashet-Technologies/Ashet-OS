/*
 * Copyright (c) 2012 Paulo Alcantara <pcacjr@zytor.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it would be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write the Free Software Foundation,
 * Inc.,  51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#ifndef XFS_READDIR_H_
#define XFS_READDIR_H_

int xfs_readdir_dir2_local(struct file *file, struct dirent *dirent,
			   xfs_dinode_t *core);
int xfs_readdir_dir2_block(struct file *file, struct dirent *dirent,
			   xfs_dinode_t *core);
int xfs_readdir_dir2_leaf(struct file *file, struct dirent *dirent,
			  xfs_dinode_t *core);
int xfs_readdir_dir2_node(struct file *file, struct dirent *dirent,
			  xfs_dinode_t *core);

#endif /* XFS_READDIR_H_ */
