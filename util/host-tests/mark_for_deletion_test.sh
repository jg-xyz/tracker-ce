#!/usr/bin/env bash
# Host test: compiles the real markedFileContains() and path-building code extracted
# from fSampleImport.cpp against a fake in-memory FileSystem.
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC=core/interface/sampleImporter/fSampleImport.cpp
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
s1=$(grep -n '^static bool markedFileContains' $SRC | cut -d: -f1)
s2=$(grep -n '^static void functMarkForDeletion()[[:space:]]*$' $SRC | cut -d: -f1)
p1=$(grep -n 'build SD-relative path' $SRC | cut -d: -f1)
p2=$(grep -n 'Path too long' $SRC | cut -d: -f1)
sed -n "${s1},$((s2-1))p" $SRC | tr -d '\r' > $d/contains.inc
sed -n "$((p1+1)),$((p2-3))p" $SRC | tr -d '\r' > $d/build.inc
cat > $d/t.cpp <<'CPP'
#include <cstdio>
#include <cstdint>
#include <algorithm>
#include <cstring>
#include <string>
#include <tuple>
static constexpr int kMaxFilePathLen = 255;
static constexpr const char* kMarkedFile = "MARKED_FOR_DELETION.txt";
struct FM{const char*p; const char* getExplorerPath(){return p;}} newFileManager;
void parseFolderName(const char* in, char* name, uint16_t* off){
  const char* s=strchr(in,'('); int a,b;
  if(s && sscanf(s,"(%d-%d)",&a,&b)==2){strncpy(name,in,s-in);name[s-in]=0;} else strcpy(name,in);
  *off=0; }
struct FileSystem {
  enum M{kRead,kWriteAppend}; typedef void* FileHandle; std::string data; size_t pos=0; bool has=false;
  bool exists(const char*){return has;}
  std::tuple<bool,FileHandle> openFile(const char*,M,FileHandle*){pos=0;return {true,this};}
  size_t readFile(void*b,size_t n,FileHandle){size_t r=std::min(n,data.size()-pos);memcpy(b,data.data()+pos,r);pos+=r;return r;}
  void closeFile(FileHandle){}
};
#include "contains.inc"
static std::string build(const char* d_,const char* item){
  newFileManager.p=d_;
  #include "build.inc"
  (void)written; return line; }
static int fails=0;
#define CHK(c) do{if(!(c)){printf("FAIL line %d: %s\n",__LINE__,#c);fails++;}}while(0)
int main(){
  CHK(build("/","a.wav")=="/a.wav");
  CHK(build("/A/B","a.wav")=="/A/B/a.wav");
  CHK(build("/","/Drums")=="/Drums/");
  CHK(build("/A","/Sub")=="/A/Sub/");
  CHK(build("/A","/Big (1-100)")=="/A/Big/");
  FileSystem fs; fs.has=true; fs.data="/a.wav\n/A/B/x.wav\n/Drums/\n";
  CHK(markedFileContains(&fs,"/A/B/x.wav")); CHK(markedFileContains(&fs,"/Drums/"));
  CHK(!markedFileContains(&fs,"/A/B")); CHK(!markedFileContains(&fs,"/a.wa"));
  fs.data="/a.wav"; CHK(!markedFileContains(&fs,"/a.wav")); // unterminated last line: not matched
  fs.has=false; CHK(!markedFileContains(&fs,"/a.wav"));
  fs.has=true; fs.data=std::string(300,'x')+"\n/ok\n"; CHK(markedFileContains(&fs,"/ok"));
  printf(fails?"FAILED\n":"mark_for_deletion: all passed\n"); return fails;
}
CPP
g++ -std=c++17 -Wall -I"$d" -o $d/t $d/t.cpp && $d/t
