# Out-of-tree build of patched ca0132 only (avoids codecs/ obj-y subdirs).
obj-m := snd-hda-codec-ca0132.o
snd-hda-codec-ca0132-y := ca0132.o
ccflags-y += -I$(src)/../linux-7.1.9/sound/hda/common
