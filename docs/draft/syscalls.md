# Syscall List Draft

# Required Changes

ashetos:
+ shared resources

- Kernel Resource System
  - All user-allocatable resources stored in a DoublyLinkedList
  - Have a common user-exposable pointer and forward/backward conversion possible
  - Queued IOPs are internally linked to the associated resource(s)
  => syscalls.resources
  => SystemResource
- Proper date/time syscalls
- Rework video out syscalls
  - Support for multiple video outputs
  => VideoOutput
- Terminate-and-stay-resident
  => process.terminate
  => process.thread.spawn
  => process.thread.kill
  => process.thread.join
  => process.thread.exit
- Window+Widget APIs
  - Register/Unregister widget
  - Create/destroy widget tree
  - Context menu APIs
  - Drag'n'Drop APIs
- Kernel Drawing/Graphics API
  - Semantic Drawing API
  - Screenshot API
    - Query semantic information
  => Framebuffer
- Update File APIs
  - Add/set mime-type
  - Store mime-type in database
- Clipboard system
  - Set
  - Get
  => clipboard.set
  => clipboard.get_type
  => clipboard.get_value
- Service Methods
  - Register/unregister service
  - Query registered services
  => service.register
  => service.unregister
  => service.count
  => service.get
- Input drivers can have an associated video output for absolute positioning
- Process monitoring functionality
  => process.monitor



