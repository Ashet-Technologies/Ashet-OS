The GUI are several types that play together:

* `Desktop` is a collection of windows
* `Window` is a collection widgets and a render target
* `Widget` is a distinct UI element, also a rendertarget
* `Framebuffers`  are rendertargets

One application creates a desktop, and others can then create windows on this desktop. Placement of Windows is 100% task of the Desktop server, the size can be requested/changed by the applications themselves

Widgets are implemented by services and processes, while other processes can also use them

Desktops arent necessarily tied to one or more screens and could be 100% virtual, or in VR or whatever 
