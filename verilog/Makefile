
all: mac.bin
include Makefile.icestorm

mac.json: bluenoise-32.hex bluenoise-64.hex bluenoise-128.hex bluenoise-256.hex

%.hex: ../images/%.png
	convert $< gray:- \
	| xxd -g1 -c1 \
	| cut -d" " -f2 \
	> $@


prog-%: %.bin
	tinyprog -p $<

prog-meta: boardmeta.json
	tinyprog -a 1 --security $<

# create a board meta file
HARDWARE_VERSION ?= v0
UUID ?= $(shell uuidgen)
BOARD_NAME ?= Pixel Wrangler
FPGA_NAME ?= $(DEVICE)-$(FOOTPRINT)

boardmeta.json: FORCE
	echo > $@ \
	'{"boardmeta":{'\
	'"name":"$(BOARD_NAME)",'\
	'"fpga":"$(FPGA_NAME)",'\
	'"hver":"$(HARDWARE_VERSION)",'\
	'"uuid":"$(UUID)"'\
	'}}'

