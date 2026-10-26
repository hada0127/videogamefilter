/* SPDX-License-Identifier: MIT. Exercise production enrollment persistence. */
#define main daemon_main_for_test
#include "service.c"
#undef main
#include <assert.h>
int main(void){
    char directory[]="/tmp/vgf-auth-XXXXXX";assert(mkdtemp(directory));root=directory;
    double times[5]={0};failures=times;const char *id="11111111-1111-1111-1111-111111111111";
    char pin_digest[65],joined[80],token[65],client[65];snprintf(joined,sizeof(joined),"%s:123456",id);digest(joined,pin_digest);
    json_object *d=json_object_new_object();json_object_object_add(d,"id",json_object_new_string(id));json_object_object_add(d,"secret",json_object_new_string("00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"));json_object_object_add(d,"pin_hash",json_object_new_string(pin_digest));json_object_object_add(d,"paired",json_object_new_boolean(0));assert(save_registry(d)==0);json_object_put(d);
    json_object *r=json_tokener_parse("{\"client\":\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\",\"pin\":\"123456\"}");
    assert(authenticate(r,token,client)==1);assert(strlen(token)==64);char original[65];strcpy(original,token);
    assert(authenticate(r,token,client)==1&&!strcmp(original,token));
    json_object_object_add(r,"client",json_object_new_string("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"));assert(authenticate(r,token,client)<0);
    json_object_object_add(r,"client",json_object_new_string("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"));assert(confirm("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")<0);
    assert(confirm("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")==0);assert(authenticate(r,token,client)<0);
    json_object_object_del(r,"pin");json_object_object_add(r,"token",json_object_new_string(original));
    for(int i=0;i<5;i++)times[i]=now_s();assert(authenticate(r,token,client)==0);
    json_object_object_add(r,"token",json_object_new_string("0000000000000000000000000000000000000000000000000000000000000000"));assert(authenticate(r,token,client)<0);
    json_object_put(r);char path[512];path_for(path,"device.json");d=json_object_from_file(path);assert(truth(d,"paired")&&!string(d,"pin_hash"));json_object_put(d);unlink(path);path_for(path,"registry.lock");unlink(path);assert(rmdir(directory)==0);
    puts("PASS PIN enrollment, same-client retry, competing-client rejection, durable confirm, token login under rate limit, wrong token rejection");return 0;
}
