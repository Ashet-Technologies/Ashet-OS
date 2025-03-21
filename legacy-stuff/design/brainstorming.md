## Project goals

- Run a Gopher browser
- Run an IRC client
- Have a simple Pokemon style game
- Edit text files on the disk
- Assemble code on-machine
- Have a tiny compiler for a tiny language (probably http://github.com/masterq32/makeshift)
- Have a music player

## Constraints

- screen size is 256×128 pixels large
  - video mode can display 256 selectable colors out of 65536
  - text mode can display 64×32 monochrome characters (foreground/background color)

## Impementation ideas

- Virtual consoles selectable with F1…F10
- Tasks that are not focused right now are "suspended" and only perform necessary work

  - Networking
  - Audio Streaming

- Co-operative multi-tasking
  - Allow priority hooking for audio rendering
  - Network handshakes are handled via regular event streams
    - No need for super low-latency communications here

## Numbers

```
Audio Playback
  audio quality: 44100 Hz
  sample size: 16 bit per sample (signed)
  samples per page: 2048
  playback duration per page: 46.4 ms
```
