CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -Wno-misleading-indentation
CPPFLAGS += $(shell pkg-config --cflags openssl json-c dbus-1 bluez)
LDLIBS += $(shell pkg-config --libs openssl json-c dbus-1 bluez) -lm
all: vgf-controller
service.o bluetooth.o protocol.o usb.o test_protocol.o test_auth.o test_session.o: protocol.h bluetooth.h usb.h
test_auth.o test_session.o: service.c
vgf-controller: service.o bluetooth.o protocol.o usb.o
	$(CC) $(CFLAGS) $^ $(LDLIBS) -o $@
check: test-protocol test-auth test-session
	./test-protocol
	./test-auth
	./test-session
test-protocol: test_protocol.o protocol.o usb.o
	$(CC) $(CFLAGS) $^ $(LDLIBS) -o $@
test-auth: test_auth.o bluetooth.o protocol.o usb.o
	$(CC) $(CFLAGS) $^ $(LDLIBS) -o $@
test-session: test_session.o bluetooth.o protocol.o usb.o
	$(CC) $(CFLAGS) $^ $(LDLIBS) -o $@
clean:
	rm -f *.o vgf-controller test-protocol test-auth test-session
.PHONY: all check clean
