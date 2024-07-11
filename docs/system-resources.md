# System Resources

## Overview

System resources are kernel resources handled out to the userland.

Each system resource is owned by at least a single process, but multiple processes may share ownership of a single resource.
 
When all processes release the resource, it will be destroyed.

## Implementation

Each process has its own pool of resource handles, which are handed to the 
userland code as an opaque pointer.

These handles use a generational mapping scheme to be able to recognize
discarded resources even if we reuse the same slot in an object slot.

These handles are resolved to a linked list node. These nodes are then linked
into the resource they represent.

This way, we have both the reference counter implemented via the linked list, and
we also linked the processes and the resources together.
