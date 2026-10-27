/* SPDX-License-Identifier: MIT. Run production session/cleanup against socket
   backpressure. Only the TLS and gadget entry points are replaced; no live HID,
   enrollment state, or service lock is accessed. */
#include <openssl/ssl.h>
#include <fcntl.h>
#include <stdarg.h>
#include <assert.h>
#include <sys/socket.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <poll.h>

static int test_tcp=-1,test_hid=-1;
static char test_lock[]="/tmp/vgf-session-XXXXXX";
static int isolated_open(const char *path,int flags,...){
    mode_t mode=0;
    if(flags&O_CREAT){va_list ap;va_start(ap,flags);mode=va_arg(ap,int);va_end(ap);}
    assert(!strcmp(path,"/run/videogamefilter-controller.lock"));
    return open(test_lock,flags,mode);
}
static int socket_usb_open(void){return test_hid;}
static int socket_usb_configured(void){return 1;}
static int rfkill_blocked=-1;
static int recorded_rfkill(int block){rfkill_blocked=block;return 1;}
static unsigned yields; /* Pure-timeout polls: the flood throttle. */
static int counting_poll(struct pollfd *f,nfds_t n,int t){if(!n&&t>=1)yields++;return poll(f,n,t);}
static int plain_write(SSL *ssl,const void *data,int n){(void)ssl;return (int)send(test_tcp,data,(size_t)n,MSG_NOSIGNAL);}
static int plain_read(SSL *ssl,void *data,int n){(void)ssl;return (int)recv(test_tcp,data,(size_t)n,0);}
static int plain_pending(const SSL *ssl){(void)ssl;return 0;}
static int plain_error(const SSL *ssl,int n){(void)ssl;return n<0&&(errno==EAGAIN||errno==EWOULDBLOCK)?SSL_ERROR_WANT_READ:SSL_ERROR_ZERO_RETURN;}

#define main daemon_main_for_test
#define open isolated_open
#define vgf_usb_open socket_usb_open
#define vgf_usb_configured socket_usb_configured
#define vgf_bt_rfkill recorded_rfkill
#define poll counting_poll
#define SSL_write plain_write
#define SSL_read plain_read
#define SSL_pending plain_pending
#define SSL_get_error plain_error
#include "service.c"
#undef main
#undef open
#undef vgf_usb_open
#undef vgf_usb_configured
#undef vgf_bt_rfkill
#undef poll
#undef SSL_write
#undef SSL_read
#undef SSL_pending
#undef SSL_get_error

static void socket_hid(int fds[2]){
    assert(socketpair(AF_UNIX,SOCK_SEQPACKET,0,fds)==0);
    int size=1024;assert(setsockopt(fds[0],SOL_SOCKET,SO_SNDBUF,&size,sizeof(size))==0);
    assert(set_nonblocking(fds[0])==0);
}
static unsigned fill_hid(int fd){
    const uint8_t filler[8]={0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa,0xaa};
    unsigned count=0;
    while(write(fd,filler,sizeof(filler))==sizeof(filler))count++;
    assert(count>0&&(errno==EAGAIN||errno==EWOULDBLOCK));return count;
}
static void wait_child(pid_t child){int status;assert(waitpid(child,&status,0)==child);assert(WIFEXITED(status)&&WEXITSTATUS(status)==0);}
static void read_transport(int tcp,unsigned char key[32],struct sockaddr_in *peer){
    char line[512];
    for(;;){
        size_t used=0;
        do{assert(used<sizeof(line)-1);assert(read(tcp,line+used,1)==1);}while(line[used++]!='\n');
        line[used]=0;json_object *o=json_tokener_parse(line);assert(o);
        const char *type=string(o,"type");
        if(type&&!strcmp(type,"transport")){
            const char *encoded=string(o,"key");unsigned char decoded[33];assert(encoded&&strlen(encoded)==44);
            assert(EVP_DecodeBlock(decoded,(const unsigned char*)encoded,44)==33);memcpy(key,decoded,32);
            json_object *port=NULL;assert(json_object_object_get_ex(o,"port",&port));
            *peer=(struct sockaddr_in){.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK),.sin_port=htons((uint16_t)json_object_get_int(port))};
            json_object_put(o);return;
        }
        json_object_put(o);
    }
}
static void send_input(int fd,const struct sockaddr_in *peer,const unsigned char key[32],uint64_t sequence,uint32_t buttons){
    uint8_t packet[VGF_PACKET_SIZE]={0};
    for(int i=7;i>=0;i--){packet[i]=(uint8_t)sequence;sequence>>=8;}
    memcpy(packet+8,"VGF2",4);for(int i=0;i<4;i++)packet[12+i]=(uint8_t)(buttons>>(8*i));
    unsigned len=0;assert(HMAC(EVP_sha256(),key,32,packet,24,packet+24,&len)&&len==32);
    assert(sendto(fd,packet,sizeof(packet),0,(const struct sockaddr*)peer,sizeof(*peer))==sizeof(packet));
}
static void usb_session_survives_stall(void){
    int hid[2],tcp[2];socket_hid(hid);unsigned filled=fill_hid(hid[0]);assert(socketpair(AF_UNIX,SOCK_STREAM,0,tcp)==0);
    pid_t child=fork();assert(child>=0);
    if(!child){
        alarm(5);close(hid[1]);close(tcp[1]);test_tcp=tcp[0];test_hid=hid[0];
        session(NULL,tcp[0],0);close(tcp[0]);assert(rfkill_blocked==1);_exit(0);
    }
    close(hid[0]);close(tcp[0]);unsigned char key[32];struct sockaddr_in peer;read_transport(tcp[1],key,&peer);
    /* The old USB 100ms cutoff exits while the host still holds its last report. */
    usleep(160000);assert(waitpid(child,NULL,WNOHANG)==0);
    int udp=socket(AF_INET,SOCK_DGRAM,0);assert(udp>=0);
    const uint32_t buttons[]={1u<<A,(1u<<A)|(1u<<B),1u<<B,0};
    for(unsigned i=0;i<4;i++)send_input(udp,&peer,key,i+1,buttons[i]);
    usleep(10000);
    uint8_t report[8];for(unsigned i=0;i<filled;i++){assert(read(hid[1],report,8)==8);assert(report[0]==0xaa);}
    unsigned edge=0;double deadline=now_s()+1;
    while(edge<4&&now_s()<deadline){
        struct pollfd p={hid[1],POLLIN,0};if(poll(&p,1,100)<=0)continue;
        assert(read(hid[1],report,8)==8);
        if(!edge&&!report[0]&&!report[1])continue; /* Pending initial neutral. */
        vgf_input expected={.buttons=buttons[edge]};uint8_t bytes[8];vgf_usb_report(&expected,bytes);
        assert(!memcmp(report,bytes,8));edge++;
    }
    assert(edge==4);
    /* At most one ack per loop, for the newest sequence; every ack is authenticated and the last is 4. */
    for(uint64_t last=0;last<4;){
        struct pollfd p={udp,POLLIN,0};assert(poll(&p,1,1000)==1);uint8_t ack[64],expected[VGF_ACK_SIZE];uint64_t seq=0;
        assert(recv(udp,ack,sizeof(ack),0)==VGF_ACK_SIZE);for(int i=0;i<8;i++)seq=(seq<<8)|ack[i];
        assert(seq>last&&seq<=4);vgf_ack(key,seq,expected);assert(!memcmp(ack,expected,VGF_ACK_SIZE));last=seq;
    }
    close(tcp[1]);wait_child(child);close(udp);close(hid[1]);
}
static void udp_flood_yields_cpu(void){
    int hid[2],tcp[2];socket_hid(hid);assert(socketpair(AF_UNIX,SOCK_STREAM,0,tcp)==0);
    pid_t child=fork();assert(child>=0);
    if(!child){
        alarm(5);close(hid[1]);close(tcp[1]);test_tcp=tcp[0];test_hid=hid[0];yields=0;
        session(NULL,tcp[0],0);close(tcp[0]);assert(yields>=1);_exit(0);
    }
    close(hid[0]);close(tcp[0]);unsigned char key[32];struct sockaddr_in peer;read_transport(tcp[1],key,&peer);
    int udp=socket(AF_INET,SOCK_DGRAM,0);assert(udp>=0);
    /* Queue more than one 64-datagram drain while the session is stopped: forged ones, then three valid. */
    assert(kill(child,SIGSTOP)==0);
    uint8_t forged[VGF_PACKET_SIZE]={0};memcpy(forged+8,"VGF2",4);
    for(int i=0;i<100;i++){forged[7]=(uint8_t)(i+1);assert(sendto(udp,forged,sizeof(forged),0,(struct sockaddr*)&peer,sizeof(peer))==sizeof(forged));}
    for(unsigned i=1;i<=3;i++)send_input(udp,&peer,key,i,1u<<A);
    assert(kill(child,SIGCONT)==0);
    /* The second drain accepts all three valid datagrams; only the newest is acknowledged. */
    struct pollfd p={udp,POLLIN,0};assert(poll(&p,1,1000)==1);uint8_t ack[64],expected[VGF_ACK_SIZE];
    assert(recv(udp,ack,sizeof(ack),0)==VGF_ACK_SIZE);vgf_ack(key,3,expected);assert(!memcmp(ack,expected,VGF_ACK_SIZE));
    assert(poll(&p,1,100)==0);
    close(tcp[1]);wait_child(child);close(udp);close(hid[1]);
}
static void usb_cleanup_releases_after_resume(void){
    int hid[2],ready[2];socket_hid(hid);unsigned filled=fill_hid(hid[0]);assert(pipe(ready)==0);
    pid_t child=fork();assert(child>=0);
    if(!child){
        alarm(3);close(hid[0]);close(ready[0]);assert(write(ready[1],"r",1)==1);close(ready[1]);
        /* Resume promptly so a busy single-core installer has scheduling margin.
           The permanently blocked case below checks both bounded wait windows. */
        usleep(5000);uint8_t report[8];
        for(unsigned i=0;i<filled;i++){assert(read(hid[1],report,8)==8);assert(report[0]==0xaa);}
        assert(read(hid[1],report,8)==8);
        const uint8_t neutral[8]={0,0,8,128,128,128,128,0};assert(!memcmp(report,neutral,8));
        close(hid[1]);_exit(0);
    }
    close(hid[1]);close(ready[1]);char signal;assert(read(ready[0],&signal,1)==1);close(ready[0]);
    vgf_protocol protocol={0};hid_release(hid[0],1,&protocol);close(hid[0]);wait_child(child);
}
static void usb_cleanup_is_bounded(void){
    int hid[2];socket_hid(hid);fill_hid(hid[0]);vgf_protocol protocol={0};
    double started=now_s();hid_release(hid[0],1,&protocol);double elapsed=now_s()-started;
    assert(elapsed>=.03&&elapsed<.5);close(hid[0]);close(hid[1]);
}
int main(void){
    signal(SIGPIPE,SIG_IGN);alarm(10);int lock=mkstemp(test_lock);assert(lock>=0);close(lock);
    usb_session_survives_stall();udp_flood_yields_cpu();usb_cleanup_releases_after_resume();usb_cleanup_is_bounded();
    assert(unlink(test_lock)==0);puts("PASS USB session survives 100ms backpressure, ordered queued edges after resume, authenticated newest-only acks, UDP flood yields 1 ms, Bluetooth radio blocked, neutral cleanup retry, bounded stalled cleanup");return 0;
}
