# Pixel Wrangler: HDMI to whatever

![Rendering of the pre-production beta board](images/pcb-3d.png)

The Pixel Wrangler is a tool for converting HDMI video into anything else.
It uses an ice40up5k FPGA to decode the video stream and stores a section
of it in the block RAM, which can then be clocked out of the 16 GPIO pins
in any other format required.

Since the FPGA has total flexibility in how it drives the output pins
it is easily adaptable to different protocols.  Some examples that are possible:

* Classic CRT monitors like B&W Mac or Hercules monitors
* LED matrices
* Flip dots
* LED strips (ws2812 or other protocols)
* Lots of servos for "wooden mirrors"

## PCB design

![Early PCB layout with air wires](images/pcb.png)

[v0 Schematic](pcb/wrangler_v0.pdf) is based on the [UPduino v3.0 by tinyvision.ai](https://www.tindie.com/products/tinyvision_ai/upduino-v31-low-cost-lattice-ice40-fpga-board/),
heavily modified for this specific application.

The HDMI connector has one differential pair carrying a 25 MHz clock and three differential
pairs running at 250 MHz and carrying 10 bits per pixel.  The clock *must* connect
to the one pin on the ice40up5k that has a LVDS connection to the global clock buffer
so that the pixel clock can be quickly fanned-out to the rest of the logic that uses it.
The three data pairs are routed to the LVDS inputs; D0 and D1 are inverted so that they
don't have to cross on the PCB and must be flipped in the logic.

## Limitations

* Only "baseline video" is supported
  * 640x480 @ 60Hz
  * 25 MHz maximum pixel clock
  * DDR might make it possible to use higher screen resolution
* 1 Mib frame buffer memory in the ice40. Resolutions supported are:
  * 1024x1024x1
  * 512x512x4
  * 256x256x16
  * 256x128x24
* 3.3V IO on GPIO pins
* No protection against shorts or overcurrent. Be careful!


## Prototyping

![Prototype on a breadboard](images/breadboard.jpg)

A prototype is working on an upduino board with an HDMI breakout adapter.
It's really surprising that it works as well as it does.


## Todo

* [X] Finish board design
* [ ] DDR on input for slower clock
* [ ] Classic Mac mode
* [ ] LED strip mode
