/* fprof.c: per-game-frame profile from a MAME trace ("<totalcycles> <PC>: <disasm>" lines,
   "   (interrupted at X, IRQ n)" markers).
   Usage: fprof <in> <out> <map> <boundary_pc_hex> <first_frame>
   map: lines "R <start> <end> <cat>" (hex ranges, half-open, category index),
        "M <addr> <idx>" (marker PCs: first-hit cycle offset per frame),
        "N <idx> <name>" (category names, echoed to the header).
   Each row: F <frame> <cycles> <instrs> <irqs> <ncat> c0 .. cN-1 <nmark> m0 .. mM-1
   A frame = the instructions between two executions of the boundary PC (the game's
   vblank-flag addq at 0x9e8); the first row is the partial frame before the first boundary. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#define NPC 0x200000
#define NCAT 64
#define NMARK 16
static uint8_t cat[NPC];
static int16_t mark[NPC];
static char names[NCAT][32];
int main(int argc, char **argv) {
  if (argc < 6) { fprintf(stderr, "usage\n"); return 1; }
  FILE *in = strcmp(argv[1], "-") ? fopen(argv[1], "r") : stdin;
  FILE *out = fopen(argv[2], "w");
  FILE *mf = fopen(argv[3], "r");
  uint32_t bpc = strtoul(argv[4], 0, 16);
  long frame = atol(argv[5]);
  int ncat = 0, nmark = 0;
  memset(cat, NCAT - 1, sizeof cat);
  for (int i = 0; i < NPC; i++) mark[i] = -1;
  char line[1024];
  while (fgets(line, sizeof line, mf)) {
    if (line[0] == 'R') { unsigned s, e, c; if (sscanf(line + 1, "%x %x %u", &s, &e, &c) == 3) { if (e > NPC) e = NPC; for (unsigned a = s; a < e; a++) cat[a] = c; if ((int)c + 1 > ncat) ncat = c + 1; } }
    else if (line[0] == 'M') { unsigned a, i; if (sscanf(line + 1, "%x %u", &a, &i) == 2 && a < NPC && i < NMARK) { mark[a] = i; if ((int)i + 1 > nmark) nmark = i + 1; } }
    else if (line[0] == 'N') { unsigned i; char nm[32]; if (sscanf(line + 1, "%u %31s", &i, nm) == 2 && i < NCAT) strcpy(names[i], nm); }
  }
  fclose(mf);
  if (ncat < NCAT) ncat = NCAT;  /* the last category = unmapped */
  fprintf(out, "# frame cycles instrs irqs ncat");
  for (int i = 0; i < ncat; i++) fprintf(out, " %s", names[i][0] ? names[i] : "-");
  fprintf(out, " nmark\n");
  uint64_t cyc[NCAT]; long long mk[NMARK];
  memset(cyc, 0, sizeof cyc); for (int i = 0; i < NMARK; i++) mk[i] = -1;
  uint64_t pcyc = 0, fstart = 0, instrs = 0, irqs = 0; uint32_t ppc = 0xffffffff; int pending_irq = 0; int started = 0;
  while (fgets(line, sizeof line, in)) {
    if (line[0] == ' ') { if (strstr(line, "interrupted")) { pending_irq = 1; irqs++; } continue; }
    char *p; uint64_t c = strtoull(line, &p, 10); if (p == line) continue;
    uint32_t pc = (uint32_t)strtoul(p + 1, &p, 16) & (NPC - 1);
    if (*p != ':') continue;
    if (!started) { started = 1; fstart = c; }
    if (ppc != 0xffffffff) { uint64_t d = c - pcyc; if (d > 100000) d = 0; cyc[cat[ppc]] += d; }
    if (pc == bpc) {
      fprintf(out, "F %ld %llu %llu %llu %d", frame, (unsigned long long)(c - fstart), (unsigned long long)instrs, (unsigned long long)irqs, ncat);
      for (int i = 0; i < ncat; i++) fprintf(out, " %llu", (unsigned long long)cyc[i]);
      fprintf(out, " %d", nmark);
      for (int i = 0; i < nmark; i++) fprintf(out, " %lld", mk[i]);
      fputc('\n', out);
      frame++; fstart = c; instrs = 0; irqs = 0; memset(cyc, 0, sizeof cyc); for (int i = 0; i < NMARK; i++) mk[i] = -1;
    }
    if (mark[pc] >= 0 && mk[mark[pc]] < 0) mk[mark[pc]] = (long long)(c - fstart);
    instrs++; pending_irq = 0;
    pcyc = c; ppc = pc;
  }
  fclose(out);
  return 0;
}
