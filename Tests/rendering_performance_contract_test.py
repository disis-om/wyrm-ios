"""Prepared-source parity and production CPU storage tests; no Apple runtime claim."""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TREE = ROOT / "build-original-source"
sys.path.insert(0, str(ROOT / "Scripts"))
import engine_performance_2026_11_04 as performance

# The snake shadow band (2026-11-06) was reverted on 2026-11-07, so the
# performance anchors are checked on a plain copy of the prepared tree.
_copy = Path(tempfile.mkdtemp()) / "tree"
for _relative in set(performance.PAIRS) | set(performance.FILES):
    _source = TREE / _relative
    if _source.exists():
        (_copy / _relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(_source, _copy / _relative)
# AIR extras (2026-11-07) edit some of the same lines: check the anchors on
# the tree without them.
import engine_air_extras_2026_11_07 as air_extras
air_extras.revert(_copy)
performance.apply(_copy, dry=True)
shutil.rmtree(_copy.parent, ignore_errors=True)
text = (TREE / "app/src/game/redraw.c").read_text(encoding="utf-8")
policy = text[text.index("static int wyrm_budget_level;"):
              text.index("static bool skin_uv_same")]
assert hashlib.sha256(policy.encode()).hexdigest() == \
    "04fc9e9347b64e444d8c5dc402048fa6b61fb73be1df273adb7fb99149ce2d6d"
for relative, expected in performance.FILES.items():
    assert (TREE / relative).read_text(encoding="utf-8") == expected
texture = (TREE / "app/src/rendering/texture.c").read_text(encoding="utf-8")
assert "vkCmdBlitImage" in texture  # Keep the Apple GPU mip generator.
assert "if (vmaFlushAllocation(ctx->allocator, up->staging_memory" in texture
main = (TREE / "app/src/main.c").read_text(encoding="utf-8")
assert "wyrm_frame_observe(!wyrm_background()" in main
assert "WyrmIOSDrawShell(env);" in main

# Compile and execute the real allocation helper with a deterministic allocator
# that moves allocations and can fail. No Vulkan/driver behavior is simulated.
helper = performance.FILES["app/src/rendering/instance_storage.h"]
helper = "\n".join(line for line in helper.splitlines() if not line.startswith("#include"))
code = r'''
typedef unsigned long size_t;
#define NULL ((void*)0)
#define SIZE_MAX ((size_t)-1)
static unsigned char storage[2][262144];
static int bank, fail_next, allocations;
static size_t previous_size;
static void* realloc(void* old, size_t size) {
  if (fail_next) { fail_next=0; return NULL; }
  if (size>sizeof(storage[0])) return NULL;
  bank=1-bank;
  if (old) for (size_t i=0;i<previous_size;i++) storage[bank][i]=((unsigned char*)old)[i];
  previous_size=size; allocations++;
  return storage[bank];
}
''' + helper + r'''
#define CHECK(x) do { if (!(x)) return __LINE__; } while(0)
__attribute__((export_name("test"))) int test(void) {
  int capacity=0;
  unsigned* data=NULL;
  CHECK(instance_storage_reserve(data,&capacity,65536,0,4)==NULL);
  CHECK(capacity==0 && allocations==0);
  for (int n=1;n<=10000;n++) {
    unsigned* grown=instance_storage_reserve(data,&capacity,65536,n,4);
    CHECK(grown && capacity>=n && capacity<=65536);
    data=grown; data[n-1]=(unsigned)(n*17);
    if (n==2049 || n==4097 || n==8193)
      for (int j=0;j<n;j++) CHECK(data[j]==(unsigned)((j+1)*17));
  }
  CHECK(allocations==4);
  int old_capacity=capacity; unsigned* old=data;
  fail_next=1;
  CHECK(instance_storage_reserve(data,&capacity,65536,capacity+1,4)==NULL);
  CHECK(capacity==old_capacity && data==old && data[9999]==170000);
  CHECK(instance_storage_reserve(data,&capacity,65536,65537,4)==NULL);
  CHECK(capacity==old_capacity);
  capacity=0;
  CHECK(instance_storage_reserve(NULL,&capacity,3,3,4)!=NULL && capacity==3);
  return 0;
}
'''
clang = Path(os.environ.get("LOCALAPPDATA", "")) / \
    "Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe"
if clang.exists():
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)
        (path / "storage.c").write_text(code, encoding="utf-8")
        subprocess.run([str(clang), "--target=wasm32", "-nostdlib", "-fno-builtin",
                        "-Wl,--no-entry", "-Wl,--export-memory", "-O2",
                        str(path / "storage.c"), "-o", str(path / "storage.wasm")], check=True)
        subprocess.run(["node", "-e",
                        "WebAssembly.instantiate(require('fs').readFileSync(process.argv[1]),{})"
                        ".then(({instance})=>{let r=instance.exports.test();"
                        "if(r)throw Error('Storage assertion line '+r);"
                        "console.log('Production storage: 10000 pushes, relocation, failure and limits PASS')})",
                        str(path / "storage.wasm")], check=True)
else:
    # macOS CI has Apple clang, not the Windows NDK path above. Execute the
    # same production helper natively instead of pretending its Wasm ran.
    host_clang = shutil.which("clang")
    if not host_clang:
        raise RuntimeError("Portable test compiler unavailable; storage execution not verified")
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)
        native = code.replace('__attribute__((export_name("test")))', '')
        native += '\nint main(void) { return test(); }\n'
        (path / "storage.c").write_text(native, encoding="utf-8")
        subprocess.run([host_clang, "-std=c11", "-fno-builtin", "-O2",
                        str(path / "storage.c"), "-o", str(path / "storage")], check=True)
        subprocess.run([str(path / "storage")], check=True)
    print("Production storage native host: 10000 pushes, relocation, failure and limits PASS")
print("46 performance anchors, helpers, protected beads, Apple mips and CPU metrics PASS")
