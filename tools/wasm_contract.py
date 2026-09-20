#!/usr/bin/env python3
"""校验 wasm 模块与 demo/main.js 之间的导入/导出契约。

main.js 用 `WebAssembly.instantiate(module, {})` 实例化，即传入空的 imports
对象——模块只能依赖引擎内置提供的导入（js-string builtins 与 "_" 命名空间下
的导入字符串常量）。任何其他导入都会导致实例化失败。本脚本静态解析二进制，
在不需要浏览器/JS 运行时的前提下把这类问题查出来。

用法:
    python tools/wasm_contract.py [path/to/moonvorbis.wasm]
"""

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_WASM = REPO / "demo" / "moonvorbis.wasm"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# 引擎通过 builtins / importedStringConstants 自动提供的导入来源
ENGINE_PROVIDED = {"wasm:js-string", "_"}


class Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def byte(self) -> int:
        b = self.data[self.pos]
        self.pos += 1
        return b

    def uleb(self) -> int:
        result = 0
        shift = 0
        while True:
            b = self.byte()
            result |= (b & 0x7F) << shift
            if not (b & 0x80):
                return result
            shift += 7

    def sleb(self) -> int:
        result = 0
        shift = 0
        while True:
            b = self.byte()
            result |= (b & 0x7F) << shift
            shift += 7
            if not (b & 0x80):
                if b & 0x40:
                    result -= 1 << shift
                return result

    def name(self) -> str:
        n = self.uleb()
        s = self.data[self.pos : self.pos + n].decode("utf-8", "replace")
        self.pos += n
        return s

    def valtype(self) -> str:
        """读取值类型。GC 提案下 (ref ht) 占两个字节，不能只读一个。"""
        b = self.byte()
        simple = {
            0x7F: "i32", 0x7E: "i64", 0x7D: "f32", 0x7C: "f64", 0x7B: "v128",
            0x70: "funcref", 0x6F: "externref",
        }
        if b in simple:
            return simple[b]
        if b in (0x63, 0x64):  # (ref null ht) / (ref ht)
            prefix = "ref null " if b == 0x63 else "ref "
            # heaptype 是 sleb128：抽象类型为负值（单字节），具体类型为类型索引
            # （≥64 时占两个字节，只读一个字节会让整个类型段解析错位）
            names = {-16: "func", -17: "extern", -18: "any", -19: "eq",
                     -20: "i31", -21: "struct", -22: "array"}
            h = self.sleb()
            return prefix + names.get(h, f"type#{h}" if h >= 0 else f"ht({h})")
        if b in (0x78, 0x77):  # packed storage type: i8 / i16
            return "i8" if b == 0x78 else "i16"
        return f"?0x{b:02x}"


def read_comptype(r: Reader):
    """读取复合类型，返回 (kind, 描述)。

    GC 提案里 functype 沿用 MVP 的 0x60 标签，新增的 struct/array 用 0x5F/0x5E。
    """
    b = r.byte()
    if b == 0x60:  # functype
        params = [r.valtype() for _ in range(r.uleb())]
        results = [r.valtype() for _ in range(r.uleb())]
        sig = " -> ".join([", ".join(params) or "()", ", ".join(results) or "()"])
        return "func", sig
    if b == 0x5F:  # structtype
        for _ in range(r.uleb()):
            r.valtype()  # field storage type（i8/i16 是 packed 编码，见 valtype）
            r.byte()     # mutability
        return "struct", "struct"
    if b in (0x5E, 0x61):  # arraytype
        r.valtype()
        r.byte()
        return "array", "array"
    raise ValueError(f"未知复合类型 0x{b:02x} @ {r.pos - 1}")


def read_subtype(r: Reader):
    """返回该 subtype 的 (kind, 描述)，调用前 pos 位于 subtype 首字节。"""
    if r.data[r.pos] in (0x50, 0x4F):  # sub / sub final，后跟 vec(supertype) 再跟 comptype
        r.byte()
        for _ in range(r.uleb()):
            r.uleb()
    return read_comptype(r)


def read_type_section(r: Reader):
    """展开类型段为扁平的类型索引表（rec group 会被平铺）。"""
    count = r.uleb()
    types = []
    for _ in range(count):
        if r.data[r.pos] == 0x4E:  # rec group
            r.byte()
            for _ in range(r.uleb()):
                types.append(read_subtype(r))
        else:
            types.append(read_subtype(r))
    return types


def parse(data: bytes):
    r = Reader(data)
    magic = data[:4]
    version = data[4:8]
    r.pos = 8

    imports, exports, types, funcs = [], [], [], []
    while r.pos < len(data):
        sec_id = r.byte()
        size = r.uleb()
        end = r.pos + size
        if sec_id == 1:  # type
            types = read_type_section(r)
            if r.pos != end:
                raise ValueError(
                    f"类型段未对齐：读完 {len(types)} 个类型后停在 {r.pos}，"
                    f"段尾在 {end}（解析假设与二进制不符，后续索引都不可信）"
                )
        elif sec_id == 3:  # function
            funcs = [r.uleb() for _ in range(r.uleb())]
        elif sec_id == 2:  # import
            for _ in range(r.uleb()):
                mod, field, kind = r.name(), r.name(), r.byte()
                if kind == 0x00:
                    desc = f"func type#{r.uleb()}"
                elif kind == 0x01:
                    desc = f"table {r.valtype()}"
                    flags = r.byte()
                    r.uleb()
                    if flags & 1:
                        r.uleb()
                elif kind == 0x02:
                    flags = r.byte()
                    r.uleb()
                    if flags & 1:
                        r.uleb()
                elif kind == 0x03:
                    desc = f"global {r.valtype()} {'mut' if r.byte() else 'const'}"
                else:
                    desc = f"kind 0x{kind:02x}"
                imports.append((mod, field, desc))
        elif sec_id == 7:  # export
            for _ in range(r.uleb()):
                name, kind, idx = r.name(), r.byte(), r.uleb()
                kindname = {0: "func", 1: "table", 2: "mem", 3: "global"}.get(kind, "?")
                exports.append((name, kindname, idx))
        r.pos = end
    n_imported_funcs = sum(1 for _, _, d in imports if d.startswith("func "))
    return magic, version, imports, exports, types, funcs, n_imported_funcs


def signature_of(export, types, funcs, n_imported_funcs):
    """导出的 func 索引落在「导入函数 + 本地函数」拼成的索引空间里。"""
    _, _, idx = export
    if idx < n_imported_funcs:
        return None  # 导入的函数，类型不在本模块类型段里
    local = idx - n_imported_funcs
    if local >= len(funcs):
        return None
    tidx = funcs[local]
    if tidx >= len(types):
        return None
    return types[tidx]


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_WASM
    data = path.read_bytes()
    magic, version, imports, exports, types, funcs, n_imported = parse(data)

    print(f"模块: {path}")
    print(f"大小: {len(data)} 字节   魔数: {magic!r}   版本: {version.hex()}\n")

    print(f"导入 ({len(imports)} 条):")
    by_mod = {}
    for mod, field, desc in imports:
        by_mod.setdefault(mod, []).append((field, desc))
    for mod, entries in sorted(by_mod.items()):
        tag = "引擎自动提供 OK" if mod in ENGINE_PROVIDED else "需要手工提供 FAIL"
        print(f"  [{mod}]  {len(entries)} 条  {tag}")
        for field, desc in entries[:4]:
            print(f"      {field}  ->  {desc}")
        if len(entries) > 4:
            print(f"      … 其余 {len(entries) - 4} 条省略")

    print(f"\n导出 ({len(exports)} 条):")
    names = [n for n, _, _ in exports]
    for name, kind, idx in exports:
        print(f"  {name}  ({kind} #{idx})")

    print()
    ok = True

    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        ok = False
        print(f"重名导出 FAIL: {sorted(dupes)}")
    else:
        print("导出名唯一 OK")

    unexpected = sorted({m for m, _, _ in imports} - ENGINE_PROVIDED)
    if unexpected:
        ok = False
        print(f"存在非引擎提供的导入 FAIL: {unexpected}")
        print("  main.js 传的是空 imports 对象，这些导入会让实例化直接失败")
    else:
        print("导入全部由引擎提供 OK")

    target = "decode_ogg_base64"
    if target in names:
        print(f"导出 {target} 存在 OK")
        export = next(e for e in exports if e[0] == target)
        sig = signature_of(export, types, funcs, n_imported)
        if sig is None:
            print(f"  {target} 的签名无法解析（类型段未覆盖）")
        else:
            kind, desc = sig
            print(f"  签名: {desc}")
            # main.js 传字符串、收字符串。wasm-gc + use-js-builtin-string 下
            # MoonBit String 就是 extern 引用，非空时编码为 (ref extern)。
            if kind == "func" and desc in ("externref -> externref", "ref extern -> ref extern"):
                print(f"  {target} 是 String -> String OK")
            else:
                ok = False
                print(f"  {target} 签名不是 String -> String FAIL（main.js 期望字符串进、字符串出）")
    else:
        ok = False
        print(f"缺少导出 {target} FAIL（main.js 调用的就是它）")

    print()
    print("契约校验:", "通过" if ok else "失败")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
