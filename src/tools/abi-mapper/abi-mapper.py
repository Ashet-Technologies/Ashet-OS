#!/usr/bin/env python3.11

import argparse
import sys
import io
import os
from typing import NoReturn 

from pathlib import Path 
from enum import StrEnum
from lark import Lark, Transformer
from dataclasses import dataclass, field 
from argparse import ArgumentParser

import caseconverter

def log(*args, **kwargs):
    if len(args) > 0:
        print(" ".join(repr(v) for v in args), file=sys.stderr)
    l = max(len(k) for k in  kwargs.keys())
    for k,v in kwargs.items():
        r = repr(v)
        try:
            r = ", ".join(repr(i) for i in v)
        except TypeError:
            pass
        print(f"{k.rjust(l)}: {r}", file=sys.stderr)


def panic(*args) -> NoReturn:
    log("PANIC:", *args)
    raise AssertionError() 

WITH_LINKNAME = False 
THIS_PATH = Path(__file__).parent 
GRAMMAR_PATH = THIS_PATH / "minizig.lark"
# ABI_PATH = THIS_PATH / ".." / ".." / "abi"/"abi-v2.zig"


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
class SystemResource(Declaration):
    pass 

@dataclass
class Function(Declaration):
    params: list[Parameter]
    return_type: Type 

@dataclass
class ErrorSet(Declaration,Type):
    errors: set[str]

@dataclass
class IOP(Declaration):
    inputs: list[Parameter]
    outputs: list[Parameter]
    error: ErrorSet
    key: str = ""

@dataclass
class Container :
    decls: list[Declaration]

@dataclass
class TopLevelCode(Container):
    rest: str


@dataclass
class ErrorAllocation:
    mapping: dict[str, int] = field(default_factory=lambda:dict())

    def get_number(self, err: str):
        val = self.mapping.get(err, None)
        if val is None:
            val = max(self.mapping.values() or [0]) + 1
            self.mapping[err] = val 
        return val
    
    def collect(self, decl: Declaration):

        if isinstance(decl, ErrorSet):
            self.insert_error_set(decl)
        elif isinstance(decl, Namespace):
            for sub in  decl.decls:
                self.collect(sub)
        elif isinstance(decl, Function):
            if isinstance( decl.return_type , ErrorSet):
                self.insert_error_set(decl.return_type)
        elif isinstance(decl, IOP):
            self.insert_error_set(decl.error)
        elif isinstance(decl, SystemResource): 
            pass
        else:
            panic("unexpected", decl)
    
    def insert_error_set(self, set: ErrorSet):
        for err in set.errors:
            self.get_number(err)

@dataclass
class ABI_Definition:
    root_container: TopLevelCode
    errors: ErrorAllocation
    iop_numbers: dict[int,IOP]
    sys_resources: list[str]

def unwrap_items(func):
    def _deco(self, items):
        return func(self, *items)
    return _deco

class ZigCodeTransformer(Transformer):

    def toplevel(self, items) -> TopLevelCode:
        return TopLevelCode(
            decls = items[0].decls,
            rest = items[1] or "",
        )

    def zigcode(self, items) -> str:
        assert len(items) == 1
        return items[0].value

    
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

    def src_decl(self, items) -> SystemResource:
        assert len(items) == 1
        return SystemResource(
            name = items[0],
            docs = None,
        )
    
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

    def err_decl(self, items) -> ErrorSet:
        etype = items[1]
        etype.name = items[0]
        return etype

    @unwrap_items
    def iop_decl(self, identifier, inputs, errorset, outputs) -> IOP:
        return IOP(
            name = identifier,
            docs = None,
            inputs = inputs,
            outputs = outputs,
            error = errorset,
        )

    def iop_struct(self, items) -> list[Parameter]:
        assert all(isinstance(item, Parameter) for item in items)
        return items

    def iop_struct_field(self, items):
        return Parameter(
            docs = items[0],
            name = items[1],
            type = items[2],
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
        print("unmapped type", items, file=sys.stderr)
        return Type()

    def ref_type(self, items) -> ReferenceType:
        return ReferenceType(name = items[0])

    def opt_type(self, items) -> OptionalType:
        return OptionalType(inner= items[0])

    def err_type(self, items) -> ErrorSet:
        if len(items) == 1 and items[0] is None:
            items = []
        return ErrorSet(errors=set(items),docs=None,name=None)

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
    elif isinstance(t, ErrorSet):
        stream.write("ErrorSet(error{")
        stream.write(",".join( t.errors))
        stream.write("})")
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
            panic("unexpected", t.size)
        
        if t.const:
            stream.write("const ")
        if t.volatile:
            stream.write("volatile ")
        if t.alignment is not None :
            stream.write(f"align({t.alignment}) ")
        
        render_type(stream, t.inner)
    else:
        panic("unexpected", t)

def render_docstring(stream ,I: str, docs: DocComment | None):
    if docs is not None:
        for line in docs.lines:
            stream.write(f"{I}/// {line}\n")

def render_container(stream, declarations: list[Declaration], errors: ErrorAllocation, indent: int = 0, prefix:str = "ashet"):
    I = "    " * indent
    for decl in declarations:
        render_docstring(stream, I, decl.docs)
        symbol = f"{prefix}_{decl.name}"

        if isinstance(decl, Namespace):
            stream.write(f"{I}pub const {decl.name} = struct {{\n")
            render_container(stream, decl.decls,errors, indent + 1, symbol)
            stream.write(f"{I}}};\n")
        elif isinstance(decl, Function):

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
        elif isinstance(decl, ErrorSet):
            

            stream.write(f"{I}pub const {decl.name} = ErrorSet(error{{\n")
            
            for err in sorted(decl.errors, key=lambda e:errors.get_number(e)):
                stream.write(f"{I}    {err},\n")

            stream.write(f"{I}}});\n")

        elif isinstance(decl, IOP):

            def write_struct_fields(struct: list[Parameter]):
                for field in struct:
                    if field.docs:
                        render_docstring(stream, I + "        ", field.docs)
                    stream.write(f"{I}         {field.name}: ")
                    render_type(stream, field.type)
                    stream.write(",\n")

            stream.write(f"{I}pub const {decl.name} = IOP.define(.{{\n")
            
            stream.write(f"{I}    .type = .@\"{decl.key}\",\n")
            if decl.error is not None:
                stream.write(f"{I}    .@\"error\" = ErrorSet(error{{\n")
                for err in sorted(decl.error.errors, key=lambda e:errors.get_number(e)):
                    stream.write(f"{I}        {err},\n")
                stream.write(f"{I}    }}),\n")
            if len(decl.inputs) > 0:
                stream.write(f"{I}    .inputs = struct {{\n")
                write_struct_fields(decl.inputs)
                stream.write(f"{I}    }},\n")
            if len(decl.outputs) > 0:
                stream.write(f"{I}    .outputs = struct {{\n")
                write_struct_fields(decl.outputs)
                stream.write(f"{I}    }},\n")

            stream.write(f"{I}}});\n")

        elif isinstance(decl, SystemResource): 
            stream.write(f"{I}pub const {decl.name} = *opaque {{\n")
            stream.write(f"{I}    pub fn as_resource(value: *@This()) *SystemResource {{\n")
            stream.write(f"{I}        return @ptrCast(value);\n")
            stream.write(f"{I}    }}\n")
            stream.write(f"{I}}};\n")

        else:
            panic("unexpected", decl)
        stream.write("\n")



def foreach(declarations: list[Declaration], T: type, func, namespace: list[str]=[]):
    for decl in declarations:
        if isinstance(decl, Namespace):
            foreach(decl.decls, T, func, namespace + [decl.name])
        elif isinstance(decl, T):
            func(decl,namespace)
        elif isinstance(decl, ErrorSet) or isinstance(decl, Function) or isinstance(decl, IOP) or isinstance(decl, SystemResource):
            pass 
        else:
            panic("unexpected", decl)

def assert_legal_extern_type(t: Type):
    
    if isinstance(t, ReferenceType):
        pass # always ok
    elif isinstance(t, OptionalType):
        assert_legal_extern_type(t.inner)
    elif isinstance(t, ArrayType):
        assert_legal_extern_type(t.inner)
    elif isinstance(t, PointerType):
        assert t.size != PointerSize.slice
    elif isinstance(t, ErrorSet):
        assert True 
    else:
        panic("unexpected", t)

def assert_legal_extern_fn(func: Function,ns:list[str]):

    for p in func.params:
        assert_legal_extern_type(p.type)
    assert_legal_extern_type(func.return_type)

def transform_parameter_list(in_params: list[Parameter]) -> list[Parameter]:
    out_params: list[Parameter] = list()
    for param in in_params:

        ptr_type = param.type
        is_out_value = False 

        if isinstance(ptr_type, PointerType) and ptr_type.size == PointerSize.one and not ptr_type.const:
            ptr_type = ptr_type.inner
            is_out_value = True
        
        # Allow single-level unwrap:
        if isinstance(ptr_type, OptionalType):
            ptr_type = ptr_type.inner

        if not isinstance(ptr_type, PointerType):
            out_params.append(param)
            continue 

        if ptr_type.size != PointerSize.slice:
            out_params.append(param)
            continue 

        if param.name is None :
            panic("bad function:", param)

        
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
        
        out_params.append(param)
        out_params.append(len_param)

    return out_params

def transform_function(func: Function,ns:list[str]):
    func.params = transform_parameter_list(func.params)

def transform_iop(iop: IOP,ns:list[str]):
    iop.inputs = transform_parameter_list(iop.inputs)
    iop.outputs = transform_parameter_list(iop.outputs)

def render_abi_definition(stream, abi: ABI_Definition):
    root_container = abi.root_container
    errors = abi.errors
    iop_numbers = abi.iop_numbers
    sys_resources = abi.sys_resources

    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!


""")

    transformed_code = ""
    with io.StringIO() as strio:
        render_container(strio, root_container.decls,errors)
        stream.write(strio.getvalue())

    stream.write(root_container.rest)
    
    with io.StringIO() as strio:
        strio.write("\n")
        strio.write("\n")
        strio.write("/// Global error set, defines numeric values for all errors.\n")
        strio.write("pub const Error = enum(u16) {\n")
        for key, value in sorted(errors.mapping.items(), key=lambda kv: kv[1]):
            assert key != "ok"
            assert key != "Unexpected"
            assert 0 < value < 0xFFFF
            strio.write(f"    {key} = {value},\n")
        strio.write("};\n")
        strio.write("\n")
        strio.write("\n")
        strio.write("/// Global error set, defines numeric values for all errors.\n")
        strio.write("pub const IOP_Type = enum(u32) {\n")
        for value, iop in sorted(iop_numbers.items(), key=lambda kv: kv[0]):
            strio.write(f"    {iop.key} = {value},\n")
        strio.write("};\n")
        strio.write("\n")
        strio.write("\n")
        strio.write("const __SystemResourceType = enum(u16) {\n")
            
        for src in sys_resources:
            strio.write(f"    {caseconverter.snakecase(src)},\n")

        strio.write("    _,\n");
        strio.write("};\n");

        strio.write("\n")
        strio.write("fn __SystemResourceCastResult(comptime t: __SystemResourceType) type {\n")
        strio.write("    return switch (t) {\n")
        
        for src in sys_resources:
            strio.write(f"        .{caseconverter.snakecase(src)} => {src},\n")

        strio.write("         _ => @compileError(\"Undefined type passed.\"),\n")
        strio.write("    };\n")
        strio.write("}\n")

        strio.write("\n")
        
        stream.write(strio.getvalue())


def render_kernel_implementation(stream, abi: ABI_Definition):
    root_container = abi.root_container
    errors = abi.errors
    iop_numbers = abi.iop_numbers
    sys_resources = abi.sys_resources

    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!


""")

def render_userland_implementation(stream, abi: ABI_Definition):
    root_container = abi.root_container
    errors = abi.errors
    iop_numbers = abi.iop_numbers
    sys_resources = abi.sys_resources

    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!


""")

class Renderer(StrEnum):
    definition = "definition"
    kernel = "kernel"
    userland = "userland"

def main():

    cli_parser = ArgumentParser()

    cli_parser.add_argument("-o", "--output", type=Path, required=False)
    cli_parser.add_argument("-m", "--mode", type=Renderer, required=False, default=Renderer.definition)
    cli_parser.add_argument("abi", type=Path)

    cli = cli_parser.parse_args()

    output_path: Path | None  = cli.output
    abi_path: Path = cli.abi
    render_mode: Renderer = cli.mode

    grammar_source = GRAMMAR_PATH.read_text()
    zig_parser = Lark(grammar_source, start='toplevel')

    source_code = abi_path.read_text()

    transformer = ZigCodeTransformer()

    parse_tree = zig_parser.parse(source_code)
    
    root_container: TopLevelCode = transformer.transform(parse_tree)

    errors = ErrorAllocation()
    for decl in root_container.decls:
        errors.collect(decl)

    # Convert all parameters of functions into extern compatible ones
    foreach(root_container.decls, Function, func=transform_function)
    
    # Convert all input/output structs of IOPs into extern compatible ones
    foreach(root_container.decls, IOP, func=transform_iop)

    
    iop_numbers: dict[int,IOP] = dict()
    
    def allocate_iop_num(iop: IOP, ns:list[str]):
        index = len(iop_numbers) + 1
        name = "_".join([*ns, iop.name])
        iop.key = name
        iop_numbers[index] = iop 
    foreach(root_container.decls, IOP, allocate_iop_num)

    iop_prefix = os.path.commonprefix([iop.key for iop in iop_numbers.values()])
    for iop in iop_numbers.values():
        iop.key = iop.key.removeprefix(iop_prefix)

    foreach(root_container.decls, Function, func=assert_legal_extern_fn)


    sys_resources: list[str] = list()
    
    def collect_src(src: SystemResource, ns:list[str]):
        name = ".".join([*ns, src.name])
        sys_resources.append(name)
    foreach(root_container.decls, SystemResource, collect_src)

    abi = ABI_Definition(
        root_container=root_container,
        errors=errors,
        iop_numbers=iop_numbers,
        sys_resources=sys_resources,
    )

    renderer = {
        Renderer.definition: render_abi_definition,
        Renderer.kernel: render_kernel_implementation,
        Renderer.userland: render_userland_implementation,
    }[render_mode]

    if output_path is not None:
        with output_path.open("w") as f:
            renderer(stream=f,abi=abi)
    else:
        renderer(stream=sys.stdout,abi=abi)

    

if __name__ == "__main__":
    main()