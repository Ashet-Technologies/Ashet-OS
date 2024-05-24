# Ashet OS Feature Drafts

- Integrated VNC server
- Automatic fallback to virtual screen if none present
- Integrated 9P server to expose file system
- 9P network file system support
- Overhaul IOP system
  - Add timeouts to all IOPs
  - Allow ordering of IOP execution
  - Add thread-affinity to IOPs
  - Add transactional file system operations
- wasm based binary format
  - AoT compiler
  - Compile-on-load (?)
  - One binary for all platforms

## System Interface Changes

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
- Input drivers can have an associated video output for absolute positioning
