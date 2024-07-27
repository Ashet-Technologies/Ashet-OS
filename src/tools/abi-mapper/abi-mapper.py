#!/usr/bin/env python3.11

import sys
import os
import re 
import hashlib
from typing import NoReturn, Optional, Any 
from collections.abc import Callable, Iterable
from contextlib import contextmanager


from pathlib import Path 
from enum import StrEnum
from lark import Lark, Transformer
from dataclasses import dataclass, field, replace as replace_field
from argparse import ArgumentParser
from typing import TypeVar, Generic

T = TypeVar('T')


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

class RefValue(Generic[T]):
    value: T

    def __init__(self, default: T = None):
        self.value = default 

    def __str__(self) -> str:
        return str(self.value)

    def __repr__(self) -> str:
        return f"ref<{self.value!r}>"

class PointerSize(StrEnum):
    one = "*"
    many = "[*]"
    slice = "[]"


@dataclass(frozen=True, eq=True)
class Type :
    ...

@dataclass(frozen=True, eq=True)
class ReferenceType(Type):
    name: str 
    
@dataclass(frozen=True, eq=True)
class OptionalType(Type):
    inner: Type 
    
@dataclass(frozen=True, eq=True)
class ArrayType(Type):
    size: str
    sentinel: str | None 
    inner: Type 

@dataclass (frozen=True, eq=True)
class PointerType(Type):
    size: PointerSize
    sentinel: str | None
    const: bool
    volatile: bool
    alignment: str | None 
    inner: Type

@dataclass(frozen=True, eq=True)
class ErrorUnion(Type):
    error: "ErrorSet"
    result: Type

@dataclass(frozen=True, eq=True)
class DocComment:
    lines: list[str]
    

@dataclass(frozen=True, eq=True)
class Declaration:
    name: str 
    docs: DocComment | None 

@dataclass(frozen=True, eq=True)
class Parameter:
    docs: DocComment | None 
    name: str | None 
    type: Type 

@dataclass(frozen=True, eq=True)
class Namespace(Declaration):
    decls: list[Declaration]

@dataclass(frozen=True, eq=True)
class SystemResource(Declaration):
    pass 

@dataclass
class ParameterAnnotation:
    is_slice: bool
    is_optional: bool
    is_out: bool
    technical: bool

    @property
    def is_regular(self) -> bool:
        return not (self.is_slice or self.is_out or self.technical)

class ParameterCollection:
    abi: list[Parameter]
    native: list[Parameter] = field(default_factory=list)
    annotations: list[ParameterAnnotation] = field(default_factory=list)

    def __init__(self, params: list[Parameter]):
        self.abi = [
            param if param.name else replace_field(param, name=f"_param{index}")
            for index, param in enumerate(params)
        ]
        self.native = list()
        self.annotations = list()

        for param in self.abi:
            
            self.append(param)
        
        assert len(self.native) >= len(self.abi)
        assert len(self.annotations) == len(self.abi)

    def append(self, param: Parameter, technical: bool = False):
        reconstruct_stack: list[Callable[[Type],Type]] = list()
        slice_type = param.type
        is_out_value = False 
        is_optional_value=False

        if isinstance(slice_type, PointerType) and slice_type.size == PointerSize.one and not slice_type.const:
            slice_type = slice_type.inner
            is_out_value = True
            reconstruct_stack.append( lambda t: PointerType(
                size=PointerSize.one,
                const=False,
                inner=t,
                sentinel=None,
                alignment=None,
                volatile=False,
            ))
        
        # Allow single-level unwrap:
        if isinstance(slice_type, OptionalType):
            slice_type = slice_type.inner
            reconstruct_stack.append( lambda t: OptionalType(inner=t))
            is_optional_value=True

        if not isinstance(slice_type, PointerType):
            self.native.append(param)
            self.annotations.append(ParameterAnnotation(
                    is_slice=False,
                    is_optional=is_optional_value,
                    is_out=False,
                    technical=technical,
                ))
            return 

        if slice_type.size != PointerSize.slice:
            self.native.append(param)
            self.annotations.append(ParameterAnnotation(
                is_slice=False,
                is_optional=is_optional_value,
                is_out=False,
                technical=technical,
            ))
            return

        if param.name is None :
            panic("bad function:", param)

        multi_ptr_type = replace_field(slice_type, size=PointerSize.many)
        for transform in reversed(reconstruct_stack):
            multi_ptr_type = transform(multi_ptr_type)

        ptr_param = Parameter(
            name = f"{param.name}_ptr",
            docs=param.docs,
            type=multi_ptr_type,
        )
        len_param = Parameter(
            name=f"{param.name}_len",
            docs=DocComment(lines=[f"Length of {param.name}_ptr"]),
            type=ReferenceType("usize"),
        )

        if is_out_value:
            len_param = replace_field(len_param, type = PointerType(
                inner = len_param.type,
                alignment=None,
                const=False,
                sentinel=None,
                size=PointerSize.one,
                volatile=False,
            ))
        self.annotations.append(ParameterAnnotation(
            is_slice=True,
            is_optional=is_optional_value,
            is_out=is_out_value,
            technical=technical,
        ))
        self.native.append(ptr_param)
        self.native.append(len_param)

    def __len__(self):
        return len(self.abi)

    def __iter__(self):
        anni = iter(self.annotations)
        nati = iter(self.native)
        
        for abi in self.abi:
            annotation = next(anni)

            if annotation.is_slice:
                ptr_p = next(nati)
                len_p = next(nati)
                natives = (ptr_p, len_p)
            else:
                natives = (next(nati),)

            yield (abi.name, annotation, abi, natives)



        


@dataclass(frozen=True, eq=True)
class Function(Declaration):
    params: ParameterCollection
    abi_return_type: Type 
    
    @property
    def native_return_type(self) -> "Type":
        if isinstance(self.abi_return_type, ErrorUnion):
            # we pass the result via out parameter,
            # and the error via return type:
            return self.abi_return_type.error
        
        return self.abi_return_type
            

@dataclass(frozen=True, eq=True)
class ErrorSet(Declaration,Type):
    errors: set[str]

@dataclass(frozen=True, eq=True)
class IOP(Declaration):
    inputs: ParameterCollection
    outputs: ParameterCollection
    error: ErrorSet
    key: RefValue[str] = field(default=RefValue[str](""))
    number: RefValue[int]= field(default=RefValue[int](None))

@dataclass(frozen=True, eq=True)
class Container :
    decls: list[Declaration]

@dataclass(frozen=True, eq=True)
class TopLevelCode(Container):
    rest: str


@dataclass(frozen=True, eq=True)
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
            if isinstance( decl.abi_return_type , ErrorSet):
                self.insert_error_set(decl.abi_return_type)
            elif isinstance(decl.abi_return_type, ErrorUnion):
                self.insert_error_set(decl.abi_return_type.error)
        elif isinstance(decl, IOP):
            self.insert_error_set(decl.error)
        elif isinstance(decl, SystemResource): 
            pass
        else:
            panic("unexpected", decl)
    
    def insert_error_set(self, set: ErrorSet):
        for err in set.errors:
            self.get_number(err)

@dataclass(frozen=True, eq=True)
class ABI_Definition:
    root_container: TopLevelCode
    errors: ErrorAllocation
    sys_resources: list[str]
    iops: list[IOP]

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
            return replace_field(items[1], docs=items[0])
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
        func = Function(
            name = items[0],
            docs = None,
            params = ParameterCollection( items[1]),
            abi_return_type = items[2],
        )

        if isinstance(func.abi_return_type, ErrorUnion):
            func.params.append(Parameter( 
                name="__return_value",
                type=PointerType(
                    size=PointerSize.one,
                    inner = func.abi_return_type.result,
                    sentinel=None,
                    const=False,
                    volatile=False,
                    alignment=None,
                ),
                docs=None,
            ), technical=True)

        return func

    @unwrap_items
    def return_type(self, error_type, result_type) -> Type:
        if error_type is not None:
            return ErrorUnion(result=result_type, error=error_type)
        else:
            return result_type

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
            inputs =ParameterCollection( inputs),
            outputs =ParameterCollection( outputs),
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
            return replace_field( items[1], docs=items[0])
        else:
            assert False 

    def raw_parameter(self, items) -> Parameter:

        if len(items) == 1: # no doc comment
            return Parameter(docs=None, name=None, type = items[0])
        elif len(items) == 2: # with doc comment
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

ZIG_BUILTIN_TYPES = { 
    "void", "noreturn",
    "bool",
    "anyopaque", 
    "f16", "f32", "f64", "f80", "f128",
    "usize", "isize",
}

def is_builtin_type(name: str) -> bool:
    if name in ZIG_BUILTIN_TYPES:
        return True
    
    if re.match(r"[ui]\d+", name):
        return True
    
    return False 

def render_type(stream, t: Type, abi_namespace: str | None = None ):

    ns_prefix = ""
    if abi_namespace is not None:
        ns_prefix = f"{abi_namespace}."

    def _ns(name: str) -> str:
        return ns_prefix + name 

    def _value(value: str) -> str:
        if value == "true" or value == "false":
            return value 
        if isinstance(value, str) and re.match(r"[a-zA-Z_][a-zA-Z_]*", value):
            return _ns(value)
        return value

    
    if isinstance(t, ReferenceType):

        if is_builtin_type(t.name):
            stream.write(t.name)
        else:
            stream.write(ns_prefix + t.name)
    elif isinstance(t, OptionalType):
        stream.write("?")
        render_type(stream, t.inner, abi_namespace)
    elif isinstance(t, ArrayType):
        if t.sentinel is not None:
            stream.write(f"[{_value(t.size)}:{_value(t.sentinel)}]")
        else:
            stream.write(f"[{_value(t.size)}]")
        render_type(stream, t.inner, abi_namespace)
    elif isinstance(t, ErrorSet):
        stream.write(ns_prefix+"ErrorSet(error{")
        stream.write(",".join( t.errors))
        stream.write("})")
    elif isinstance(t, PointerType):
        if t.size == PointerSize.one:
            stream.write("*")
        elif t.size == PointerSize.many:
            stream.write("[*")
            if t.sentinel is not None:
                stream.write(f":{_value(t.sentinel)}")
            stream.write("]")
        elif t.size == PointerSize.slice:
            stream.write("[")
            if t.sentinel is not None:
                stream.write(f":{_value(t.sentinel)}")
            stream.write("]")
        else:
            panic("unexpected", t.size)
        
        if t.const:
            stream.write("const ")
        if t.volatile:
            stream.write("volatile ")
        if t.alignment is not None :
            stream.write(f"align({t.alignment}) ")
        
        render_type(stream, t.inner, abi_namespace)
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
                stream.write(f'{I}extern fn @"{symbol}"(')
                
            if len(decl.params.native) > 0:
                stream.write("\n")
            
                for param in decl.params.native:
                    stream.write(f"{I}    ")
                    if param.name is not None:
                        stream.write(f"{param.name}: ")
                    render_type(stream, param.type)
                    stream.write(",\n")
                stream.write(I)

            stream.write(f") ")

            if WITH_LINKNAME:
                stream.write(f"linkname(\"{symbol}\") ")

            render_type(stream, decl.native_return_type)

            stream.write(f";\n")

            stream.write(f'{I}pub const {decl.name} = @"{symbol}";\n')

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
            if len(decl.inputs.native) > 0:
                stream.write(f"{I}    .inputs = struct {{\n")
                write_struct_fields(decl.inputs.native)
                stream.write(f"{I}    }},\n")
            if len(decl.outputs.native) > 0:
                stream.write(f"{I}    .outputs = struct {{\n")
                write_struct_fields(decl.outputs.native)
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

def assert_legal_extern_fn(func: Function, ns: list[str]):
    for p in func.params.native:
        assert_legal_extern_type(p.type)
    assert_legal_extern_type(func.native_return_type)



def render_abi_definition(stream, abi: ABI_Definition):
    root_container = abi.root_container
    errors = abi.errors
    sys_resources = abi.sys_resources

    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!


""")

    render_container(stream, root_container.decls,errors)

    stream.write(root_container.rest)
    
    stream.write("\n")
    stream.write("\n")
    stream.write("/// Global error set, defines numeric values for all errors.\n")
    stream.write("pub const Error = enum(u16) {\n")
    for key, value in sorted(errors.mapping.items(), key=lambda kv: kv[1]):
        assert key != "ok"
        assert key != "Unexpected"
        assert 0 < value < 0xFFFF
        stream.write(f"    {key} = {value},\n")
    stream.write("};\n")
    stream.write("\n")
    stream.write("\n")
    stream.write("/// IO operation type, defines numeric values for IOPs.\n")
    stream.write("pub const IOP_Type = enum(u32) {\n")
    for iop in sorted(abi.iops, key=lambda iop: iop.number.value):
        stream.write(f"    {iop.key.value} = {iop.number.value},\n")
    stream.write("};\n")
    stream.write("\n")
    stream.write("\n")
    stream.write("const __SystemResourceType = enum(u16) {\n")
        
    for src in sys_resources:
        stream.write(f"    {caseconverter.snakecase(src)},\n")

    stream.write("    _,\n");
    stream.write("};\n");

    stream.write("\n")
    stream.write("fn __SystemResourceCastResult(comptime t: __SystemResourceType) type {\n")
    stream.write("    return switch (t) {\n")
    
    for src in sys_resources:
        stream.write(f"        .{caseconverter.snakecase(src)} => {src},\n")

    stream.write("         _ => @compileError(\"Undefined type passed.\"),\n")
    stream.write("    };\n")
    stream.write("}\n")

    stream.write("\n")
    


def render_kernel_implementation(stream, abi: ABI_Definition):
    root_container = abi.root_container
    errors = abi.errors
    sys_resources = abi.sys_resources

    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!
const std = @import("std");
const abi = @import("abi");

/// This function creates a type that, when references,
/// will export all ashet os systemcalls.
///
/// Syscalls will are expected to be in their respective
/// namespace as in the ABI file.
pub fn create_exports(comptime Impl: type) type {
    return struct {
""")

    def get_error_set_name(es: Iterable[str], prefix: str) -> str:
        return prefix + hashlib.sha1("\x00".join(sorted(set(es))).encode()).hexdigest()

    required_errorset_unwraps: set[tuple[str,... ]] = set ()
    def depend_on_error_set(es: ErrorSet) -> str:
        required_errorset_unwraps.add(tuple(sorted(es.errors)))
        return get_error_set_name(es.errors, '')


    def emit_impl(func: Function, ns: list[str]):
        emit_name = "_".join(("ashet", *ns, func.name))
        import_name = ".".join(("Impl", *ns, func.name))
        stream.write(f'        export fn @"{emit_name}"(')

        if len(func.params) > 0:
            first=True
            for param in func.params.native:
                if not first: stream.write(", ")
                first = False 
                stream.write(f"{param.name}: ")
                render_type(stream, param.type,abi_namespace="abi")
        
        stream.write(') ')
        render_type(stream, func.native_return_type, abi_namespace="abi")
        stream.write(' { \n')

        out_slices: list[tuple[str,str,str]] = list()
        for name, annotation, abi, natives in func.params:

            if not annotation.is_slice:
                continue 
            if not annotation.is_out:
                continue 

            assert len(natives) == 2
            
            slice_name = f"{name}__slice"

            out_slices.append((slice_name, natives[0].name, natives[1].name, annotation.is_optional))
            stream.write(f"            var {slice_name}: ")
            assert isinstance(abi.type, PointerType)
            render_type(stream, abi.type.inner, abi_namespace="abi")

            if annotation.is_optional:
                stream.write(f" = if({natives[0].name}.*) |__ptr| __ptr[0..{natives[1].name}.*] else null;\n")
            else:
                stream.write(f" = {natives[0].name}.*[0..{natives[1].name}.*];\n")

        stream.write("            ")

        if isinstance(func.abi_return_type, ErrorUnion):
            error_union: ErrorUnion = func.abi_return_type
            error_set_name = depend_on_error_set(error_union.error)

            @contextmanager
            def handle_call():

                stream.write(f"const __error_union: ZigErrorSet_{error_set_name}!");
                render_type(stream, error_union.result)
                stream.write(" = ")

                yield   

                stream.write("if(__error_union) |__result| {\n")
                stream.write("  __return_value.* = __result;\n")
                stream.write("  return .ok;\n")
                stream.write("} else |__err| {\n")
                stream.write(f"  return __unwrap_{error_set_name}(__err);\n")
                stream.write("}\n")


        elif isinstance(func.native_return_type, ErrorSet):
            error_set: ErrorSet = func.native_return_type
            error_set_name = depend_on_error_set(error_set)

            @contextmanager 
            def handle_call():
                stream.write(f"const __error_union: ZigErrorSet_{error_set_name}!void = ")

                yield 

                stream.write("if(__error_union) |_| {\n")
                stream.write("  return .ok;\n")
                stream.write("} else |__err| {\n")
                stream.write(f"  return __unwrap_{error_set_name}(__err);\n")
                stream.write("}\n")

        else:

            @contextmanager
            def handle_call():
                stream.write("const __result = ")
                yield 
                stream.write("return __result;\n")


        args: list[str] = list()
        for name, annotation, abi, natives in func.params:

            if annotation.is_slice:
                assert len(natives) == 2
                (ptr_p, len_p ) = natives

                if annotation.is_optional:
                    if annotation.is_out:
                        args.append(f"&{name}__slice")
                    else:
                        args.append(f"if ({ptr_p.name}) |__ptr| __ptr[0..{len_p.name}] else null")
                else: # not optional
                    if annotation.is_out:
                        args.append(f"&{name}__slice")
                    else:
                        args.append(f"{ptr_p.name}[0..{len_p.name}]")

            else:
                assert len(natives) == 1
                args.append(natives[0].name)

        with handle_call():

            stream.write(f"{import_name}(\n")
            for arg in args:
                stream.write(f"                {arg},\n")
            stream.write(f"            );\n")

            for slice_name, ptr_name, len_name, is_optional in out_slices:
                if is_optional:
                    stream.write(f"            {ptr_name}.* = if ({slice_name}) |__slice| __slice.ptr else null;\n")
                    stream.write(f"            {len_name}.* = if ({slice_name}) |__slice| __slice.len else 0;\n")
                else:
                    stream.write(f"            {ptr_name}.* = {slice_name}.ptr;\n")
                    stream.write(f"            {len_name}.* = {slice_name}.len;\n")


        stream.write("        }\n")
        stream.write("\n")

    foreach(root_container.decls, Function, func=emit_impl)

    stream.write("    };\n")
    stream.write("}\n")

    stream.write("\n")

    for error_set in sorted(required_errorset_unwraps):

        

        def write_error_type():
            stream.write("error{")
            stream.write(",".join(error_set))
            stream.write("}")
        
        stream.write(f"const {get_error_set_name(error_set, 'ZigErrorSet_')} = ")
        write_error_type()
        stream.write(";\n")

        stream.write(f"const {get_error_set_name(error_set, 'AbiErrorSet_')} = abi.ErrorSet(")
        stream.write(get_error_set_name(error_set, 'ZigErrorSet_'))
        stream.write(");\n")

        stream.write(f"fn __unwrap_{get_error_set_name(error_set, '')}(__error: ")
        stream.write(get_error_set_name(error_set, "ZigErrorSet_"))
        stream.write(") ")
        stream.write(get_error_set_name(error_set, "AbiErrorSet_"))
        stream.write(" {\n")
        stream.write("                return switch (__error) {\n")
        for error in error_set:
            stream.write(f"                    error.{error} => .{error},\n")
        stream.write("                };\n")

        stream.write("}\n")


def render_userland_implementation(stream, abi: ABI_Definition):
    root_container = abi.root_container
    errors = abi.errors
    sys_resources = abi.sys_resources

    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!

const std = @import("std");
const abi = @import("abi");

""")
    def emit_impl(func: Function, ns: tuple[str,...]):
        abi_name = ".".join(("abi", *ns, func.name))
        stream.write(f'        pub fn @"{func.name}"(')

        if len(func.params) > 0:
            first=True
            for param in func.params.abi:
                if not first: stream.write(", ")
                first = False 
                stream.write(f"{param.name}: ")
                render_type(stream, param.type,abi_namespace="abi")
        
        stream.write(') ')

        if isinstance(func.native_return_type, ErrorSet):
            error_set: ErrorSet = func.native_return_type
            stream.write("error{ ")
            stream.write(", ".join((*error_set.errors, "Unexpected")))
            stream.write(" }!void")

            @contextmanager
            def handle_call():

                stream.write("const __error_value = ")

                yield 


                stream.write("            return switch (__error_value) {\n")
                stream.write("                .ok => {},\n")
                stream.write("                _ => error.Unexpected,\n")
                for error in error_set.errors:
                    stream.write(f"               .{error} => error.{error},\n")
                stream.write("            };\n")

        else:

            @contextmanager
            def handle_call():
                stream.write("const __result = ")
                yield 
                stream.write("            return __result;\n")



            render_type(stream, func.native_return_type, abi_namespace="abi")
        stream.write(' { \n')

        out_slices: list[tuple[str,str,str]] = list()
        for name, annotation, abi, natives in func.params:

            if not annotation.is_slice:
                continue 
            if not annotation.is_out:
                continue 
            
            slice_name = f"{name}__slice"

            out_slices.append((name, f"{slice_name}_ptr", f"{slice_name}_len", annotation.is_optional))
            stream.write(f"            var {slice_name}_ptr: ")
            assert isinstance(natives[0].type, PointerType)
            render_type(stream, natives[0].type.inner, abi_namespace="abi")
            if isinstance(natives[0].type.inner, OptionalType):
                stream.write(f" = if({abi.name}.*) |__slice| __slice.ptr else null;\n")
            else:
                stream.write(f" = {name}.ptr;\n")
             
            if annotation.is_optional:
                stream.write(f"            var {slice_name}_len: usize = if({abi.name}.*) |__slice| __slice.len else 0;\n")
            else:
                stream.write(f"            var {slice_name}_len: usize = {abi.name}.len;\n")

        stream.write("            ")

        with handle_call():

            args: list[str] = list()
            for name, annotation, abi, natives in func.params:

                if annotation.is_slice:
                    assert len(natives) == 2
                    (ptr_p, len_p ) = natives

                    if annotation.is_optional:
                        if annotation.is_out:
                            args.append(f"&{name}__slice_ptr")
                            args.append(f"&{name}__slice_len")
                        else:
                            args.append(f"if ({name}) |__slice| __slice.ptr else null")
                            args.append(f"if ({name}) |__slice| __slice.len else 0")
                    else: # not optional
                        if annotation.is_out:
                            args.append(f"&{name}__slice_ptr")
                            args.append(f"&{name}__slice_len")
                        else:
                            args.append(f"{name}.ptr")
                            args.append(f"{name}.len")

                else:
                    assert len(natives) == 1
                    args.append(natives[0].name)

            stream.write(f'{abi_name}(\n')
            for arg in args:
                stream.write(f"                {arg},\n")
            stream.write(f"            );\n")

            for slice_name, ptr_name, len_name, is_optional in out_slices:
                if is_optional:
                    stream.write(f"            {slice_name}.* = if ({ptr_name}) |__ptr| __ptr[0..{len_name}] else null;\n")
                else:
                    stream.write(f"            {slice_name}.* = {ptr_name}[0..{len_name}];\n")


        stream.write("        }\n")
        stream.write("\n")

    def recursive_render(decls: list[Declaration], ns_prefix: tuple[str,...] = tuple()):
        for decl in decls:
            if isinstance(decl, Namespace):
                stream.write(f"pub const {decl.name} = struct {{\n")
                recursive_render(decl.decls, (*ns_prefix, decl.name))
                stream.write("};\n")
                stream.write("\n")
            elif isinstance(decl, Function):
                emit_impl(decl, ns_prefix)
            elif isinstance(decl, ErrorSet) or isinstance(decl, IOP) or isinstance(decl, SystemResource):
                pass 
            else:
                panic("unexpected", decl)
    recursive_render(root_container.decls)

class Renderer(StrEnum):
    definition = "definition"
    kernel = "kernel"
    userland = "userland"

def main():
    global WITH_LINKNAME

    cli_parser = ArgumentParser()

    cli_parser.add_argument("--output", type=Path, required=False)
    cli_parser.add_argument("--mode", type=Renderer, required=False, default=Renderer.definition)
    cli_parser.add_argument("--use-linkname", action="store_true", required=False)
    cli_parser.add_argument("abi", type=Path)

    cli = cli_parser.parse_args()

    output_path: Path | None  = cli.output
    abi_path: Path = cli.abi
    render_mode: Renderer = cli.mode
    WITH_LINKNAME = cli.use_linkname

    grammar_source = GRAMMAR_PATH.read_text()
    zig_parser = Lark(grammar_source, start='toplevel')

    source_code = abi_path.read_text()

    transformer = ZigCodeTransformer()

    parse_tree = zig_parser.parse(source_code)
    
    root_container: TopLevelCode = transformer.transform(parse_tree)

    errors = ErrorAllocation()
    for decl in root_container.decls:
        errors.collect(decl)

    iop_numbers: dict[int,IOP] = dict()
     
    def allocate_iop_num(iop: IOP, ns:list[str]):
        index = len(iop_numbers) + 1
        name = "_".join([*ns, iop.name])
        iop.key.value = name
        iop.number.value = index 
        iop_numbers[index] = iop
    foreach(root_container.decls, IOP, allocate_iop_num)

    print(iop_numbers)

    if len(iop_numbers) > 1:
        iop_prefix = os.path.commonprefix([iop.key.value for iop in iop_numbers.values()])
        for iop in iop_numbers.values():
            old = iop.key.value
            iop.key.value = iop.key.value.removeprefix(iop_prefix)
            print(repr(old), repr(iop.key.value))

    foreach(root_container.decls, Function, func=assert_legal_extern_fn)


    sys_resources: list[str] = list()
    
    def collect_src(src: SystemResource, ns:list[str]):
        name = ".".join([*ns, src.name])
        sys_resources.append(name)
    foreach(root_container.decls, SystemResource, collect_src)

    abi = ABI_Definition(
        root_container=root_container,
        errors=errors,
        sys_resources=sys_resources,
        iops=list(iop_numbers.values())
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