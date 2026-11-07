// Mirrors audio_unified.c play-ring arithmetic exactly (producer: bytes via dataBuffSetData; consumer: int16 idx, +256 mod 768)
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define SC 128
#define CH 2
#define SPC (CH*SC)
#define NB 3
int16_t buf[SPC*NB]; uint16_t len=sizeof(buf), wridx=0, rdidx=0;
void setd(uint8_t*src,int bytes){ uint8_t*b=(uint8_t*)buf;
 if(wridx+bytes<len){memcpy(&b[wridx],src,bytes);wridx+=bytes;}
 else{int e=len-wridx;memcpy(&b[wridx],src,e);wridx=bytes-e;memcpy(&b[0],src+e,wridx);} }
int main(){ int16_t next=0; int32_t pend=0; long bad=0, blocks=0; int16_t expect=0; int16_t pk[CH*45];
 // producer: 44/45-frame packets (5.5 frames/uF * 8 -> alternating), consumer: one 128-frame block when >=128 buffered (after 256 prefill)
 int ready=0, toggle=0;
 for(int it=0; it<200000; it++){
  int fr = (toggle++&1)?45:44; if(it%8==7) fr=44;
  for(int i=0;i<fr*CH;i++) pk[i]=next++;
  setd((uint8_t*)pk, fr*CH*2); pend+=fr;
  if(pend>2*SC) ready=1;
  while(ready && pend>=SC){ // ideal consumer, unmodified arithmetic
   for(int i=0;i<SC;i++){ int16_t l=buf[rdidx+i*CH], r=buf[rdidx+i*CH+1];
     if(l!=expect||r!=(int16_t)(expect+1)) bad++; expect+=2; }
   pend-=SC; rdidx+=SPC; rdidx%=SPC*NB; blocks++; }
 }
 printf("blocks=%ld mismatched_frames=%ld\n",blocks,bad); return bad!=0; }
