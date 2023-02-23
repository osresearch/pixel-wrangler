
all: mac.bin

%.hex: ../images/%.png
	convert $< gray:- \
	| xxd -g1 -c1 \
	| cut -d" " -f2 \
	> $@

#bluenoise-32.hex: ../images/bluenoise-32.png

include Makefile.icestorm
