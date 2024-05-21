#!/usr/bin/env python3.11

from operator import truediv
import sys
import io 
import jinja2

from pathlib import Path 
from enum import StrEnum 
from lark import Lark, Transformer
from dataclasses import dataclass

WITH_LINKNAME = False 
THIS_PATH = Path(__file__).parent 
GRAMMAR_PATH = THIS_PATH / "minizig.lark"
SYSCALL_PATH = THIS_PATH / ".." / "src"/"abi"/"syscalls.zig"
ABI_PATH = THIS_PATH / ".." / "src"/"abi"/"abi-v2.zig"

class PointerSize(StrEnum):
    one = "*"
    many = "[*]"
    slice = "[]"

class Type :
    ...

@dataclass
class ReferenceType(Type):
    name: str 
    
@dataclass
class OptionalType(Type):
    inner: Type 
    
@dataclass
class ArrayType(Type):
    size: str
    sentinel: str | None 
    inner: Type 

@dataclass 
class PointerType(Type):
    size: PointerSize
    sentinel: str | None
    const: bool
    volatile: bool
    alignment: str | None 
    inner: Type


@dataclass
class DocComment:
    lines: list[str]
    

@dataclass
class Declaration:
    name: str 
    docs: DocComment | None 

@dataclass
class Parameter:
    docs: DocComment | None 
    name: str | None 
    type: Type 

@dataclass
class Namespace(Declaration):
    decls: list[Declaration]

@dataclass
class Function(Declaration):
    params: list[Parameter]
    return_type: Type 

@dataclass
class Container :
    decls: list[Declaration]


class ZigCodeTransformer(Transformer):
    
    def container(self, items) -> Container:
        return Container(decls = items )

    def decl(self, items) -> Declaration: 

        if len(items) == 1: # no doc comment
            return items[0]
        elif len(items) == 2: # with doc comment
            items[1].docs = items[0]
            return items[1]
        else:
            assert False 

    def raw_decl(self, items) -> Declaration:
        assert len(items) == 1
        return items[0]
    
    def fn_decl(self, items) -> Function:
        return Function(
            name = items[0],
            docs = None,
            params = items[1],
            return_type = items[2],
        )

    def ns_decl(self, items) -> Namespace:
        return Namespace(
            name = items[0],
            docs = None,
            decls = items[1].decls,
        )

    def param_list(self, items) -> list[Parameter]:
        assert len(items) >= 1
        if items[0] is None: # special case: empty list
            assert len(items) == 1
            return []
        return items

    def parameter(self, items) -> Parameter:
        if len(items) == 1: # no doc comment
            return items[0]
        elif len(items) == 2: # with doc comment
            items[1].docs = items[0]
            return items[1]
        else:
            assert False 

    def raw_parameter(self, items) -> Parameter:

        if len(items) == 1: # no doc comment
            return Parameter(docs=None, name=None, type = items[0])
        elif len(items) == 2: # with doc comment
            items[1].docs = items[0]
            return Parameter(docs=None, name=items[0], type=items[1])
        else:
            assert False 

    def type(self, items) -> Type:
        assert len(items) == 1
        if isinstance(items[0], Type):
            return items[0]
        print("unmapped type", items)
        return Type()

    def ref_type(self, items) -> ReferenceType:
        return ReferenceType(name = items[0])

    def opt_type(self, items) -> OptionalType:
        return OptionalType(inner= items[0])

    def arr_type(self, items) -> ArrayType:
        return ArrayType(
            inner = items[2],
            size=items[0],
            sentinel=items[1],
        )
    
    def ptr_type(self, items) -> PointerType:

        size, sentinel = items[0]
        mods = items[1]

        return PointerType(
            inner = items[2],
            size=size, 
            sentinel=sentinel,
            const = mods.get("const", False),
            volatile = mods.get("volatile", False),
            alignment = mods.get("alignment", None),
        )       
    
    def ptr_size(self, items) -> tuple[PointerSize, str|None ]:
        
        if len(items) == 0: # "*"
            return (PointerSize.one, None)
        assert len(items) == 1
        return items[0]
       
    def ptr_size_many(self, items) -> tuple[PointerSize, str|None]:
        if len(items) == 1:
            return (PointerSize.many, items[0])
        assert len(items) == 0
        return (PointerSize.many, None)

    def ptr_size_slice(self, items) -> tuple[PointerSize, str|None]:
        if len(items) == 1:
            return (PointerSize.slice, items[0])
        assert len(items) == 0
        return (PointerSize.slice, None)

    def ptr_mods(self, items) -> dict[str,str]:
        mods = {
            k: v
            for mod in items
            for k, v in mod.items()
        }
        return mods
    
    def ptr_const(self, items):
        assert len(items) == 0
        return {"const": True }

    def ptr_volatile(self, items):
        assert len(items) == 0
        return {"volatile": True }

    def ptr_align(self, items):
        assert len(items) == 1
        return {"alignment": items[0]}
    
    def value(self, items):
        return items[0]

    def integer(self, items):
        assert len(items) == 1
        return int(items[0].value)

    def identifier(self, items):
        assert len(items) == 1
        return items[0].value

    def doc_comment(self, items) -> DocComment:
        return  DocComment(lines=items)
        
    def doc_comment_line(self, items):
        return items[0].value.lstrip("///").strip()

def render_type(stream, t: Type):
    
    if isinstance(t, ReferenceType):
        stream.write(t.name)
    elif isinstance(t, OptionalType):
        stream.write("?")
        render_type(stream, t.inner)
    elif isinstance(t, ArrayType):
        if t.sentinel is not None:
            stream.write(f"[{t.size}:{t.sentinel}]")
        else:
            stream.write(f"[{t.size}]")
        render_type(stream, t.inner)
    elif isinstance(t, PointerType):
        if t.size == PointerSize.one:
            stream.write("*")
        elif t.size == PointerSize.many:
            stream.write("[*")
            if t.sentinel is not None:
                stream.write(f":{t.sentinel}")
            stream.write("]")
        elif t.size == PointerSize.slice:
            stream.write("[")
            if t.sentinel is not None:
                stream.write(f":{t.sentinel}")
            stream.write("]")
        else:
            assert False 
        
        if t.const:
            stream.write("const ")
        if t.volatile:
            stream.write("volatile ")
        if t.alignment is not None :
            stream.write(f"align({t.alignment}) ")
        
        render_type(stream, t.inner)
    else:
        assert False 

def render_container(stream, declarations: list[Declaration], indent: int = 0, prefix:str = "ashet.syscall"):
    I = "    " * indent
    for decl in declarations:
        if decl.docs is not None:
            for line in decl.docs.lines:
                stream.write(f"{I}/// {line}\n")

        if isinstance(decl, Namespace):
            stream.write(f"{I}pub const {decl.name} = struct {{\n")
            render_container(stream, decl.decls, indent + 1, prefix + "." + decl.name)
            stream.write(f"{I}}};\n")
        elif isinstance(decl, Function):
            symbol = f"{prefix}.{decl.name}"

            if WITH_LINKNAME:
                stream.write(f"{I}pub extern fn {decl.name}(")
            else:
                stream.write(f"{I}pub const {decl.name} = @extern(*const fn(")
                
            if len(decl.params) > 0:

                stream.write("\n")
            
                for param in decl.params:
                    stream.write(f"{I}    ")
                    if param.name is not None:
                        stream.write(f"{param.name}: ")
                    render_type(stream, param.type)
                    stream.write(",\n")
                stream.write(I)

            stream.write(f") ")

            if WITH_LINKNAME:
                stream.write(f"linkname(\"{symbol}\") ")

            render_type(stream, decl.return_type)
            
            if not WITH_LINKNAME:
                stream.write(f", .{{ .name = \"{symbol}\" }})")

            stream.write(f";\n")
        else:
            assert False 
        stream.write("\n")

def foreach_fn(declarations: list[Declaration], func):
    for decl in declarations:
        if isinstance(decl, Namespace):
            foreach_fn(decl.decls, func)
        elif isinstance(decl, Function):
            func(decl)
        else:
            assert False 

def assert_legal_extern_type(t: Type):
    
    if isinstance(t, ReferenceType):
        pass # always ok
    elif isinstance(t, OptionalType):
        assert_legal_extern_type(t.inner)
    elif isinstance(t, ArrayType):
        assert_legal_extern_type(t.inner)
    elif isinstance(t, PointerType):
        assert t.size != PointerSize.slice
    else:
        assert False 

def assert_legal_extern_fn(func: Function):

    for p in func.params:
        assert_legal_extern_type(p.type)
    assert_legal_extern_type(func.return_type)


def transform_function(func: Function):

    new_params: list[Parameter] = list()

    for param in func.params:

        pass # TODO: add source transformations here

        ptr_type = param.type
        is_out_value = False 

        if isinstance(ptr_type, PointerType) and ptr_type.size == PointerSize.one and not ptr_type.const:
            ptr_type = ptr_type.inner
            is_out_value = True
        
        # Allow single-level unwrap:
        if isinstance(ptr_type, OptionalType):
            ptr_type = ptr_type.inner

        if not isinstance(ptr_type, PointerType):
            new_params.append(param)
            continue 

        if ptr_type.size != PointerSize.slice:
            new_params.append(param)
            continue 

        if param.name is None :
            print("bad function:", func.name, file=sys.stderr)
            assert False 

        
        len_param = Parameter(
            name=f"{param.name}_len",
            docs=DocComment(lines=[f"Length of {param.name}_ptr"]),
            type=ReferenceType("usize"),
        )

        param.name += "_ptr"
        ptr_type.size = PointerSize.many

        if is_out_value:
            len_param.type = PointerType(
                inner = len_param.type,
                alignment=None,
                const=False,
                sentinel=None,
                size=PointerSize.one,
                volatile=False,
            )
        
        new_params.append(param)
        new_params.append(len_param)

    func.params = new_params

def main():

    grammar_source = GRAMMAR_PATH.read_text()
    zig_parser = Lark(grammar_source, start='container')
    
    environment = jinja2.Environment()
    abi_template = environment.from_string(ABI_PATH.read_text())

    source_code = SYSCALL_PATH.read_text()

    transformer = ZigCodeTransformer()

    parse_tree = zig_parser.parse(source_code)
    
    root_container = transformer.transform(parse_tree)

    foreach_fn(root_container.decls, func=transform_function)

    foreach_fn(root_container.decls, func=assert_legal_extern_fn)

    syscalls_code = ""
    with io.StringIO() as strio:
        render_container(strio, root_container.decls)
        syscalls_code = strio.getvalue()

    sys.stdout.write(abi_template.render(
        syscalls="\n\n" + syscalls_code,
    ))
    

if __name__ == "__main__":
    main()