#!/usr/bin/env bash
# Host test: compiles the real name-history methods extracted from mtKeyboardManager.cpp
# against a stub class with the same members (display calls stubbed).
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC=core/source/mtKeyboardManager.cpp
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
a=$(grep -n '^void mtKeyboardManager::applyAutoName' $SRC | cut -d: -f1)
b=$(grep -n '^char\* mtKeyboardManager::getName' $SRC | cut -d: -f1)
sed -n "${a},$((b-1))p" $SRC | tr -d '\r' > $d/body.inc
cat > $d/t.cpp <<'CPP'
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
constexpr uint8_t MAX_NAME_LENGTH = 33;
constexpr uint8_t RANDOM_NAME_HISTORY_SIZE = 10;
struct Gen { int n=0; std::string s; const char* getRandomName(void*){ s="name"+std::to_string(n++); return s.c_str(); } } randomNameGenerator;
struct K {
  struct { int selectionWidth=0, selectionStart=0; } editNameData;
  uint8_t nameLengthLimit=32; int editPosition=0; char name[MAX_NAME_LENGTH]={0}; void* timer=nullptr;
  char randomNameHistory[RANDOM_NAME_HISTORY_SIZE][MAX_NAME_LENGTH];
  uint8_t randomNameHistoryHead=0, randomNameHistoryCount=0, randomNameHistoryCursor=0;
  void showKeyboardEditName(){}
  void applyAutoName(const char*); void setRandomName(); void setPreviousRandomName();
  void clearRandomNameHistory(); const char* getRandomNameHistoryEntry(uint8_t) const; void pushRandomNameHistory(const char*);
};
#define mtKeyboardManager K
#include "body.inc"
#undef mtKeyboardManager
static int fails=0;
#define EQ(a,b) do{ if(strcmp((a),(b))){printf("FAIL line %d: '%s' != '%s'\n",__LINE__,(a),(b));fails++;} }while(0)
int main(){
  K k;
  k.setPreviousRandomName(); EQ(k.name,"");                 // nothing generated: no-op (name uninit-safe)
  for(int i=0;i<4;i++) k.setRandomName();                    // name0..name3
  EQ(k.name,"name3");
  k.setPreviousRandomName(); EQ(k.name,"name2");
  k.setPreviousRandomName(); EQ(k.name,"name1");
  k.setPreviousRandomName(); EQ(k.name,"name0");
  k.setPreviousRandomName(); EQ(k.name,"name0");             // stops at oldest
  k.setRandomName(); EQ(k.name,"name4");                     // new name after stepping back
  k.setPreviousRandomName(); EQ(k.name,"name3");             // history continues from newest
  for(int i=0;i<20;i++) k.setRandomName();                   // wrap the ring
  EQ(k.name,"name24");
  for(int i=0;i<20;i++) k.setPreviousRandomName();
  EQ(k.name,"name15");                                       // window = last 10: name15..name24
  k.clearRandomNameHistory(); k.setPreviousRandomName(); EQ(k.name,"name15"); // cleared: no-op
  k.nameLengthLimit=4; k.setRandomName(); EQ(k.name,"name");  // truncated by limit
  k.setRandomName(); k.setPreviousRandomName(); EQ(k.name,"name");
  printf(fails?"FAILED\n":"autoname history: all passed\n"); return fails;
}
CPP
g++ -std=c++17 -Wall -I$d -o $d/t $d/t.cpp 2>&1 | head -20 && $d/t
