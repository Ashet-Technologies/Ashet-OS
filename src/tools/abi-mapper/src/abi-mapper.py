#!/usr/bin/env python3.11

import sys
import os
import re
import hashlib
import io
import subprocess
import caseconverter
from typing import NoReturn, Optional, Any
from collections.abc import Callable, Iterable
from contextlib import contextmanager


from pathlib import Path
from enum import StrEnum
from lark import Lark, Transformer
from dataclasses import dataclass, field, replace as replace_field
from argparse import ArgumentParser
from typing import TypeVar, Generic

T = TypeVar("T")


def log(*args, **kwargs):
    if len(args) > 0:
        print(" ".join(repr(v) for v in args), file=sys.stderr)
    l = max(len(k) for k in kwargs.keys())
    for k, v in kwargs.items():
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
class Type: ...


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


@dataclass(frozen=True, eq=True)
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
    full_qualified_name: RefValue[str] = field(
        kw_only=True, default_factory=lambda: RefValue[str](None)
    )


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
        reconstruct_stack: list[Callable[[Type], Type]] = list()
        slice_type = param.type
        is_out_value = False
        is_optional_value = False

        if (
            isinstance(slice_type, PointerType)
            and slice_type.size == PointerSize.one
            and not slice_type.const
        ):
            slice_type = slice_type.inner
            is_out_value = True
            reconstruct_stack.append(
                lambda t: PointerType(
                    size=PointerSize.one,
                    const=False,
                    inner=t,
                    sentinel=None,
                    alignment=None,
                    volatile=False,
                )
            )

        # Allow single-level unwrap:
        if isinstance(slice_type, OptionalType):
            slice_type = slice_type.inner
            reconstruct_stack.append(lambda t: OptionalType(inner=t))
            is_optional_value = True

        if not isinstance(slice_type, PointerType):
            self.native.append(param)
            self.annotations.append(
                ParameterAnnotation(
                    is_slice=False,
                    is_optional=is_optional_value,
                    is_out=False,
                    technical=technical,
                )
            )
            return

        if slice_type.size != PointerSize.slice:
            self.native.append(param)
            self.annotations.append(
                ParameterAnnotation(
                    is_slice=False,
                    is_optional=is_optional_value,
                    is_out=False,
                    technical=technical,
                )
            )
            return

        if param.name is None:
            panic("bad function:", param)

        multi_ptr_type = replace_field(slice_type, size=PointerSize.many)
        for transform in reversed(reconstruct_stack):
            multi_ptr_type = transform(multi_ptr_type)

        ptr_param = Parameter(
            name=f"{param.name}_ptr",
            docs=param.docs,
            type=multi_ptr_type,
        )
        len_param = Parameter(
            name=f"{param.name}_len",
            docs=DocComment(lines=[f"Length of {param.name}_ptr"]),
            type=ReferenceType("usize"),
        )

        if is_out_value:
            len_param = replace_field(
                len_param,
                type=PointerType(
                    inner=len_param.type,
                    alignment=None,
                    const=False,
                    sentinel=None,
                    size=PointerSize.one,
                    volatile=False,
                ),
            )
        self.annotations.append(
            ParameterAnnotation(
                is_slice=True,
                is_optional=is_optional_value,
                is_out=is_out_value,
                technical=technical,
            )
        )
        self.native.append(ptr_param)
        self.native.append(len_param)

    @property
    def has_native_params(self) -> bool:
        return len(self.native) > 0

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
class EnumeratedComponent:
    """
    A component that can be listed in an enumeration.
    """

    key: RefValue[str] = field(kw_only=True, default_factory=lambda: RefValue[str](""))
    number: RefValue[int] = field(
        kw_only=True, default_factory=lambda: RefValue[int](None)
    )


@dataclass(frozen=True, eq=True)
class Function(Declaration, EnumeratedComponent):
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
class ErrorSet(Declaration, Type):
    errors: set[str]


@dataclass(frozen=True, eq=True)
class AsyncOp(Declaration, EnumeratedComponent):
    inputs: ParameterCollection
    outputs: ParameterCollection
    error: ErrorSet


@dataclass(frozen=True, eq=True)
class Container:
    decls: list[Declaration]


@dataclass(frozen=True, eq=True)
class TopLevelCode(Container):
    rest: str


@dataclass(frozen=True, eq=True)
class ErrorAllocation:
    mapping: dict[str, int] = field(default_factory=lambda: dict())

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
            for sub in decl.decls:
                self.collect(sub)
        elif isinstance(decl, Function):
            if isinstance(decl.abi_return_type, ErrorSet):
                self.insert_error_set(decl.abi_return_type)
            elif isinstance(decl.abi_return_type, ErrorUnion):
                self.insert_error_set(decl.abi_return_type.error)
        elif isinstance(decl, AsyncOp):
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
    iops: list[AsyncOp]
    syscalls: list[Function]


def unwrap_items(func):
    def _deco(self, items):
        return func(self, *items)

    return _deco


class ZigCodeTransformer(Transformer):
    def toplevel(self, items) -> TopLevelCode:
        return TopLevelCode(
            decls=items[0].decls,
            rest=items[1] or "",
        )

    def zigcode(self, items) -> str:
        assert len(items) == 1
        return items[0].value

    def container(self, items) -> Container:
        return Container(decls=items)

    def decl(self, items) -> Declaration:
        if len(items) == 1:  # no doc comment
            return items[0]
        elif len(items) == 2:  # with doc comment
            return replace_field(items[1], docs=items[0])
        else:
            assert False

    def raw_decl(self, items) -> Declaration:
        assert len(items) == 1
        return items[0]

    def src_decl(self, items) -> SystemResource:
        assert len(items) == 1
        return SystemResource(
            name=items[0],
            docs=None,
        )

    def fn_decl(self, items) -> Function:
        func = Function(
            name=items[0],
            docs=None,
            params=ParameterCollection(items[1]),
            abi_return_type=items[2],
        )

        if isinstance(func.abi_return_type, ErrorUnion):
            func.params.append(
                Parameter(
                    name="__return_value",
                    type=PointerType(
                        size=PointerSize.one,
                        inner=func.abi_return_type.result,
                        sentinel=None,
                        const=False,
                        volatile=False,
                        alignment=None,
                    ),
                    docs=None,
                ),
                technical=True,
            )

        return func

    @unwrap_items
    def return_type(self, error_type, result_type) -> Type:
        if error_type is not None:
            return ErrorUnion(result=result_type, error=error_type)
        else:
            return result_type

    def ns_decl(self, items) -> Namespace:
        return Namespace(
            name=items[0],
            docs=None,
            decls=items[1].decls,
        )

    def err_decl(self, items) -> ErrorSet:
        etype = items[1]
        etype.name = items[0]
        return etype

    @unwrap_items
    def iop_decl(self, identifier, inputs, errorset, outputs) -> AsyncOp:
        return AsyncOp(
            name=identifier,
            docs=None,
            inputs=ParameterCollection(inputs),
            outputs=ParameterCollection(outputs),
            error=errorset,
        )

    def iop_struct(self, items) -> list[Parameter]:
        assert all(isinstance(item, Parameter) for item in items)
        return items

    def iop_struct_field(self, items):
        return Parameter(
            docs=items[0],
            name=items[1],
            type=items[2],
        )

    def param_list(self, items) -> list[Parameter]:
        assert len(items) >= 1
        if items[0] is None:  # special case: empty list
            assert len(items) == 1
            return []
        return items

    def parameter(self, items) -> Parameter:
        if len(items) == 1:  # no doc comment
            return items[0]
        elif len(items) == 2:  # with doc comment
            return replace_field(items[1], docs=items[0])
        else:
            assert False

    def raw_parameter(self, items) -> Parameter:
        if len(items) == 1:  # no doc comment
            return Parameter(docs=None, name=None, type=items[0])
        elif len(items) == 2:  # with doc comment
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
        return ReferenceType(name=items[0])

    def opt_type(self, items) -> OptionalType:
        return OptionalType(inner=items[0])

    def err_type(self, items) -> ErrorSet:
        if len(items) == 1 and items[0] is None:
            items = []
        return ErrorSet(errors=set(items), docs=None, name=None)

    def arr_type(self, items) -> ArrayType:
        return ArrayType(
            inner=items[2],
            size=items[0],
            sentinel=items[1],
        )

    def ptr_type(self, items) -> PointerType:
        size, sentinel = items[0]
        mods = items[1]

        return PointerType(
            inner=items[2],
            size=size,
            sentinel=sentinel,
            const=mods.get("const", False),
            volatile=mods.get("volatile", False),
            alignment=mods.get("alignment", None),
        )

    def ptr_size(self, items) -> tuple[PointerSize, str | None]:
        if len(items) == 0:  # "*"
            return (PointerSize.one, None)
        assert len(items) == 1
        return items[0]

    def ptr_size_many(self, items) -> tuple[PointerSize, str | None]:
        if len(items) == 1:
            return (PointerSize.many, items[0])
        assert len(items) == 0
        return (PointerSize.many, None)

    def ptr_size_slice(self, items) -> tuple[PointerSize, str | None]:
        if len(items) == 1:
            return (PointerSize.slice, items[0])
        assert len(items) == 0
        return (PointerSize.slice, None)

    def ptr_mods(self, items) -> dict[str, str]:
        mods = {k: v for mod in items for k, v in mod.items()}
        return mods

    def ptr_const(self, items):
        assert len(items) == 0
        return {"const": True}

    def ptr_volatile(self, items):
        assert len(items) == 0
        return {"volatile": True}

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
        return DocComment(lines=items)

    def doc_comment_line(self, items):
        return items[0].value.lstrip("///").strip()


ZIG_BUILTIN_TYPES = {
    "void",
    "noreturn",
    "bool",
    "anyopaque",
    "f16",
    "f32",
    "f64",
    "f80",
    "f128",
    "usize",
    "isize",
}


def is_builtin_type(name: str) -> bool:
    if name in ZIG_BUILTIN_TYPES:
        return True

    if re.match(r"[ui]\d+", name):
        return True

    return False


class CodeStream(io.TextIOBase):
    _target: io.TextIOBase
    _indent: int
    _line_buffer: str

    def __init__(self, target: io.TextIOBase):
        assert target is not None
        self._target = target
        self._indent = 0
        self._line_buffer = ""

    def _get_emit_text(self, text: str) -> str:
        self._line_buffer += text

        out = ""
        while "\n" in self._line_buffer:
            i = self._line_buffer.index("\n")
            out += "    " * self._indent
            out += self._line_buffer[0 : i + 1]
            self._line_buffer = self._line_buffer[i + 1 :]

        return out

    def write(self, *args: str) -> int:
        out = self._get_emit_text("".join(args))
        return self._target.write(out)

    def writeln(self, *args: str) -> int:
        return self.write(*args, "\n")

    @contextmanager
    def indent(self):
        self._indent += 1
        try:
            yield
        finally:
            self._indent -= 1


def render_type(stream: CodeStream, t: Type, abi_namespace: str | None = None):
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
        stream.write(ns_prefix, "ErrorSet(error{")
        stream.write(",".join(t.errors))
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
        if t.alignment is not None:
            stream.write(f"align({t.alignment}) ")

        render_type(stream, t.inner, abi_namespace)
    else:
        panic("unexpected", t)


def render_docstring(stream: CodeStream, docs: DocComment | None):
    if docs is not None:
        for line in docs.lines:
            stream.writeln(f"/// {line}")


def render_error_set(stream: CodeStream, error_set: ErrorSet | set[str]):
    if isinstance(error_set, ErrorSet):
        error_set = error_set.errors
    error_set: list[str] = sorted(set(error_set))

    if len(error_set) > 1:
        stream.writeln("error {")
        with stream.indent():
            for err in error_set:
                stream.writeln(err, ",")
        stream.writeln("}")

    else:
        stream.write("error {", ", ".join(error_set), "}")


def render_arc_type(stream: CodeStream, iop: AsyncOp):
    def write_struct_fields(
        struct: list[Parameter],
        default_factory: Callable[[Parameter], str] | None = None,
    ):
        for field in struct:
            if field.docs:
                render_docstring(stream, field.docs)
            stream.write(f"{field.name}: ")
            render_type(stream, field.type)
            if default_factory is not None:
                stream.write(" = ")
                stream.write(default_factory(field))
            stream.writeln(",")

    stream.writeln("extern struct {")
    with stream.indent():
        stream.writeln("const Self = @This();")
        # stream.writeln()
        # render_docstring(stream,DocComment(
        #     lines=[
        #                 "Marker used to recognize types as I/O ops.",
        #                 "This marker cannot be accessed outside this file, so *all* IOPs must be",
        #                 "defined in this file.",
        #                 "This allows a certain safety against programming mistakes, as a foreign type cannot be accidently marked as an IOP.",
        #     ]))
        # stream.writeln("const iop_marker = IOP_Tag;")
        stream.writeln()

        stream.writeln(f"pub const arc_type: ARC_Type = .{iop.key};")
        stream.writeln()

        stream.writeln("pub const Inputs = extern struct {")
        with stream.indent():
            write_struct_fields(iop.inputs.native)
        stream.writeln("};")
        stream.writeln("pub const Outputs = extern struct {")
        with stream.indent():
            write_struct_fields(
                iop.outputs.native, default_factory=lambda f: "undefined"
            )
        stream.writeln("};")
        stream.write("pub const Error = ")
        render_error_set(stream, iop.error)
        stream.writeln(";")

        stream.writeln("arc: ARC = .{")
        with stream.indent():
            stream.writeln(".type = arc_type,")
            stream.writeln(".tag = 0,")
        stream.writeln("},")
        stream.writeln('@"error": ErrorSet(Error) = undefined,')
        stream.writeln("inputs: Inputs,")
        stream.writeln("outputs: Outputs = undefined,")

        stream.writeln("")
        stream.writeln("")

        # TODO: Render transform of NewArgs to Input
        # stream.writeln("pub const NewArgs = struct {")
        # with stream.indent():
        #     write_struct_fields(iop.inputs.abi)
        # stream.writeln("};")

        stream.writeln(
            """
        pub fn new(__inputs: Inputs) Self {
            return Self{ .inputs = __inputs };
        }

        pub fn set_ok(val: *Self) void {
            val.@"error" = .ok;
        }

        pub fn from_arc(arc: *ARC) *Self {
            return @fieldParentPtr("arc", @as(*align(@alignOf(Self)) ARC, @alignCast(arc)));
        }
        """
        )

        stream.writeln("pub fn set_error(val: *Self, err: Error) void {")
        with stream.indent():
            stream.writeln('val.@"error" = switch(err) {')
            with stream.indent():
                for err in sorted(iop.error.errors):
                    stream.writeln(f"error.{err} => .{err},")
            stream.writeln("};")
        stream.writeln("}")
        stream.writeln()

        stream.writeln(
            "pub fn check_error(val: Self) (Error||error{Unexpected})!void {"
        )
        with stream.indent():
            stream.writeln('return switch(val.@"error") {')
            with stream.indent():
                stream.writeln(".ok => {},")
                for err in sorted(iop.error.errors):
                    stream.writeln(f".{err} => error.{err},")
                stream.writeln("_ => error.Unexpected,")
            stream.writeln("};")
        stream.writeln("}")

    stream.writeln("}")


def render_container(
    stream: CodeStream,
    declarations: list[Declaration],
    errors: ErrorAllocation,
    prefix: str = "ashet",
):
    for decl in declarations:
        render_docstring(stream, decl.docs)
        symbol = f"{prefix}_{decl.name}"

        if isinstance(decl, Namespace):
            stream.writeln(f"pub const {decl.name} = struct {{")
            with stream.indent():
                render_container(stream, decl.decls, errors, symbol)
            stream.writeln("};")
        elif isinstance(decl, Function):
            if WITH_LINKNAME:
                stream.write(f"pub extern fn {decl.name}(")
            else:
                stream.write(f'extern fn @"{symbol}"(')

            if len(decl.params.native) > 0:
                stream.writeln()

                for param in decl.params.native:
                    stream.write("    ")
                    if param.name is not None:
                        stream.write(f"{param.name}: ")
                    render_type(stream, param.type)
                    stream.writeln(",")

            stream.write(") ")

            if WITH_LINKNAME:
                stream.write(f'linkname("{symbol}") ')

            render_type(stream, decl.native_return_type)

            stream.writeln(";")

            stream.writeln(f'pub const {decl.name} = @"{symbol}";')

        elif isinstance(decl, ErrorSet):
            stream.writeln(f"pub const {decl.name} = ErrorSet(error{{")

            for err in sorted(decl.errors, key=lambda e: errors.get_number(e)):
                stream.writeln(f"    {err},")

            stream.writeln("});")

        elif isinstance(decl, AsyncOp):
            stream.write(f"pub const {decl.name} = ")
            render_arc_type(stream, decl)
            stream.writeln(";")

        elif isinstance(decl, SystemResource):
            stream.writeln(f"pub const {decl.name} = *opaque {{")
            with stream.indent():
                stream.writeln("pub fn as_resource(self: *@This()) SystemResource {")
                with stream.indent():
                    stream.writeln("return @enumFromInt(@intFromPtr(self));")
                stream.writeln("}")
                stream.writeln()
                stream.writeln("pub fn release(self: *@This()) void {")
                with stream.indent():
                    stream.writeln("resources.release(self.as_resource());")
                stream.writeln("}")
                stream.writeln()
                stream.writeln("pub fn destroy_now(self: *@This()) void {")
                with stream.indent():
                    stream.writeln("resources.destroy(self.as_resource());")
                stream.writeln("}")
            stream.writeln("};")

        else:
            panic("unexpected", decl)
        stream.writeln()


def foreach(declarations: list[Declaration], T: type, func, namespace: list[str] = []):
    for decl in declarations:
        if isinstance(decl, Namespace):
            foreach(decl.decls, T, func, namespace + [decl.name])
        elif isinstance(decl, T):
            func(decl, namespace)
        elif (
            isinstance(decl, ErrorSet)
            or isinstance(decl, Function)
            or isinstance(decl, AsyncOp)
            or isinstance(decl, SystemResource)
        ):
            pass
        else:
            panic("unexpected", decl)


def assert_legal_extern_type(t: Type):
    if isinstance(t, ReferenceType):
        pass  # always ok
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


def render_abi_definition(stream: CodeStream, abi: ABI_Definition):
    root_container = abi.root_container
    errors = abi.errors
    sys_resources = abi.sys_resources

    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!


""")

    render_container(stream, root_container.decls, errors)

    stream.write(root_container.rest)

    stream.writeln()
    # stream.writeln()
    # stream.writeln("/// Global error set, defines numeric values for all errors.")
    # stream.writeln("pub const Error = enum(u16) {")
    # for key, value in sorted(errors.mapping.items(), key=lambda kv: kv[1]):
    #     assert key != "ok"
    #     assert key != "Unexpected"
    #     assert 0 < value < 0xFFFF
    #     stream.writeln(f"    {key} = {value},")
    # stream.writeln("};")
    # stream.writeln()
    stream.writeln()
    stream.writeln(
        "/// Asynchronous operation type, defines numeric values for AsyncOps."
    )
    stream.writeln("pub const ARC_Type = enum(u32) {")
    with stream.indent():
        for iop in sorted(abi.iops, key=lambda iop: iop.number.value):
            stream.writeln(f"{iop.key.value} = {iop.number.value},")

        stream.writeln()

        stream.writeln("pub fn as_type(comptime arc_type: @This()) type {")
        with stream.indent():
            stream.writeln("return switch(arc_type) {")
            with stream.indent():
                for iop in sorted(abi.iops, key=lambda iop: iop.number.value):
                    stream.writeln(
                        f".{iop.key.value} => {iop.full_qualified_name.value},"
                    )

            stream.writeln("};")
        stream.writeln("}")

    stream.writeln()
    stream.writeln()
    stream.writeln()
    stream.writeln("};")
    stream.writeln()
    stream.writeln()
    stream.writeln("const __SystemResourceType = enum(u16) {")
    with stream.indent():
        # stream.writeln("bad_handle = 0,")

        for src in sys_resources:
            stream.writeln(f"{caseconverter.snakecase(src)},")

    # stream.writeln("    _,")
    stream.writeln("};")

    stream.writeln()
    stream.writeln(
        "fn __SystemResourceCastResult(comptime t: __SystemResourceType) type {"
    )
    stream.writeln("    return switch (t) {")

    for src in sys_resources:
        stream.writeln(f"        .{caseconverter.snakecase(src)} => {src},")

    # stream.writeln("         _ => @compileError(\"Undefined type passed.\"),")
    stream.writeln("    };")
    stream.writeln("}")

    stream.writeln()


class ErrorSetMapper:
    requested_types: set[tuple[str, ...]] = set()

    def __init__(self):
        self.requested_types = set()

    @staticmethod
    def get_error_set_name(es: Iterable[str], prefix: str) -> str:
        return prefix + hashlib.sha1("\x00".join(sorted(set(es))).encode()).hexdigest()

    def get_zig_error_type(self, es: ErrorSet) -> str:
        self.requested_types.add(tuple(sorted(es.errors)))
        return ErrorSetMapper.get_error_set_name(es.errors, "__ZigError_")

    def get_native_error_type(self, es: ErrorSet) -> str:
        self.requested_types.add(tuple(sorted(es.errors)))
        return ErrorSetMapper.get_error_set_name(es.errors, "__AbiError_")

    def get_native_to_zig_mapper(self, es: ErrorSet) -> str:
        self.requested_types.add(tuple(sorted(es.errors)))
        return "__unwrap_n2z_" + ErrorSetMapper.get_error_set_name(es.errors, "")

    def get_zig_to_native_mapper(self, es: ErrorSet) -> str:
        self.requested_types.add(tuple(sorted(es.errors)))
        return "__unwrap_z2n_" + ErrorSetMapper.get_error_set_name(es.errors, "")

    def _render_type_defs(
        self, stream: CodeStream, error_set: Iterable[str], with_unexpected: bool
    ):
        def write_error_type():
            stream.write("error{")
            stream.write(",".join(error_set))
            stream.write("}")

        # we have to insert the "Unexpected" here, as
        # the other side might have more error codes
        stream.write(
            f"const {ErrorSetMapper.get_error_set_name(error_set, '__ZigError_')} = "
        )
        write_error_type()
        if with_unexpected:
            stream.write(" || error {Unexpected}")
        stream.writeln(";")

        stream.write(
            f"const {ErrorSetMapper.get_error_set_name(error_set, '__AbiError_')} = abi.ErrorSet("
        )
        write_error_type()
        stream.writeln(");")

    def render_zig_to_native_mappers(self, stream: CodeStream) -> None:
        for error_set in sorted(self.requested_types):
            self._render_type_defs(stream, error_set, False)

            stream.write(
                f"fn __unwrap_z2n_{ErrorSetMapper.get_error_set_name(error_set, '')}(__error: "
            )
            stream.write(ErrorSetMapper.get_error_set_name(error_set, "__ZigError_"))
            stream.write(") ")
            stream.write(ErrorSetMapper.get_error_set_name(error_set, "__AbiError_"))
            stream.writeln(" {")
            with stream.indent():
                stream.writeln("return switch (__error) {")
                with stream.indent():
                    for error in error_set:
                        stream.writeln(f"error.{error} => .{error},")
                stream.writeln("};")

            stream.writeln("}")
            stream.writeln()

    def render_native_to_zig_mappers(self, stream: CodeStream) -> None:
        for error_set in sorted(self.requested_types):
            self._render_type_defs(stream, error_set, True)

            stream.write(
                f"fn __unwrap_n2z_{ErrorSetMapper.get_error_set_name(error_set, '')}(__error: "
            )
            stream.write(ErrorSetMapper.get_error_set_name(error_set, "__AbiError_"))
            stream.write(") ")
            stream.write(ErrorSetMapper.get_error_set_name(error_set, "__ZigError_"))
            stream.writeln(" {")
            with stream.indent():
                stream.writeln("return switch (__error) {")
                with stream.indent():
                    stream.writeln(
                        ".ok => unreachable, // must be checked before calling!"
                    )
                    for error in error_set:
                        stream.writeln(f".{error} => error.{error},")
                    stream.writeln("_ => error.Unexpected,")
                stream.writeln("};")

            stream.writeln("}")
            stream.writeln()


def render_kernel_implementation(stream, abi: ABI_Definition):
    root_container = abi.root_container

    all_error_sets = ErrorSetMapper()

    def emit_impl(func: Function, ns: list[str]):
        emit_name = "_".join(("ashet", *ns, func.name))
        import_name = ".".join(("Impl", *ns, func.name))
        stream.write(f'pub export fn @"{emit_name}"(')

        if func.params.has_native_params:
            first = True
            for param in func.params.native:
                if not first:
                    stream.write(", ")
                first = False
                stream.write(f"{param.name}: ")
                render_type(stream, param.type, abi_namespace="abi")

        stream.write(") ")
        render_type(stream, func.native_return_type, abi_namespace="abi")
        stream.writeln(" { ")
        with stream.indent():
            stream.writeln(f"Callbacks.before_syscall(.{func.key.value});")
            stream.writeln(f"defer Callbacks.after_syscall(.{func.key.value});")

            out_slices: list[tuple[str, str, str]] = list()
            for name, annotation, abi, natives in func.params:
                if not annotation.is_slice:
                    continue
                if not annotation.is_out:
                    continue

                assert len(natives) == 2

                slice_name = f"{name}__slice"

                out_slices.append(
                    (
                        slice_name,
                        natives[0].name,
                        natives[1].name,
                        annotation.is_optional,
                    )
                )
                stream.write(f"var {slice_name}: ")
                assert isinstance(abi.type, PointerType)
                render_type(stream, abi.type.inner, abi_namespace="abi")

                if annotation.is_optional:
                    stream.writeln(
                        f" = if({natives[0].name}.*) |__ptr| __ptr[0..{natives[1].name}.*] else null;"
                    )
                else:
                    stream.writeln(f" = {natives[0].name}.*[0..{natives[1].name}.*];")

            if isinstance(func.abi_return_type, ErrorUnion):
                error_union: ErrorUnion = func.abi_return_type

                @contextmanager
                def handle_call():
                    stream.write(
                        f"const __error_union: {all_error_sets.get_zig_error_type(error_union.error)}!"
                    )
                    render_type(stream, error_union.result, abi_namespace="abi")
                    stream.write(" = ")

                    yield

                    stream.writeln("if(__error_union) |__result| {")
                    with stream.indent():
                        stream.writeln("__return_value.* = __result;")
                        stream.writeln("return .ok;")
                    stream.writeln("} else |__err| {")
                    with stream.indent():
                        stream.writeln(
                            f"return {all_error_sets.get_zig_to_native_mapper(error_union.error)}(__err);"
                        )
                    stream.writeln("}")

            elif isinstance(func.native_return_type, ErrorSet):
                error_set: ErrorSet = func.native_return_type

                @contextmanager
                def handle_call():
                    stream.write(
                        f"const __error_union: {all_error_sets.get_zig_error_type(error_set)}!void = "
                    )

                    yield

                    stream.writeln("if(__error_union) |_| {")
                    with stream.indent():
                        stream.writeln("return .ok;")
                    stream.writeln("} else |__err| {")
                    with stream.indent():
                        stream.writeln(
                            f"return {all_error_sets.get_zig_to_native_mapper(error_set)}(__err);"
                        )
                    stream.writeln("}")

            else:

                @contextmanager
                def handle_call():
                    stream.write("const __result = ")
                    yield
                    stream.writeln("return __result;")

            args: list[str] = list()
            for name, annotation, abi, natives in func.params:
                if annotation.is_slice:
                    assert len(natives) == 2
                    (ptr_p, len_p) = natives

                    if annotation.is_optional:
                        if annotation.is_out:
                            args.append(f"&{name}__slice")
                        else:
                            args.append(
                                f"if ({ptr_p.name}) |__ptr| __ptr[0..{len_p.name}] else null"
                            )
                    else:  # not optional
                        if annotation.is_out:
                            args.append(f"&{name}__slice")
                        else:
                            args.append(f"{ptr_p.name}[0..{len_p.name}]")

                else:
                    assert len(natives) == 1
                    args.append(natives[0].name)

            with handle_call():
                stream.writeln(f"{import_name}(")
                with stream.indent():
                    for arg in args:
                        stream.writeln(f"{arg},")
                stream.writeln(");")

                for slice_name, ptr_name, len_name, is_optional in out_slices:
                    if is_optional:
                        stream.writeln(
                            f"{ptr_name}.* = if ({slice_name}) |__slice| __slice.ptr else null;"
                        )
                        stream.writeln(
                            f"{len_name}.* = if ({slice_name}) |__slice| __slice.len else 0;"
                        )
                    else:
                        stream.writeln(f"{ptr_name}.* = {slice_name}.ptr;")
                        stream.writeln(f"{len_name}.* = {slice_name}.len;")

        stream.writeln("}")
        stream.writeln()

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
pub fn create_exports(comptime Impl: type, comptime Callbacks: type) type {

    return struct {
""")

    with stream.indent():
        with stream.indent():
            foreach(root_container.decls, Function, func=emit_impl)
        stream.writeln("};")
    stream.writeln("}")

    stream.writeln()

    stream.writeln("/// Enumeration of all syscall numbers.")
    stream.writeln("pub const Syscall_ID = enum(u32) {")
    for sc in sorted(abi.syscalls, key=lambda sc: sc.number.value):
        stream.writeln(f"    {sc.key.value} = {sc.number.value},")
    stream.writeln("};")

    stream.writeln()

    all_error_sets.render_zig_to_native_mappers(stream)


@dataclass
class GenParam:
    before_call: Callable[[], None]
    before_return: Callable[[], None]
    signature: list[Parameter]
    invocation: list[str]


def render_parameter_list(stream: CodeStream, params: Iterable[Parameter]):
    first = True
    for param in params:
        if not first:
            stream.write(", ")
        first = False
        stream.write(f"{param.name}: ")
        render_type(stream, param.type, abi_namespace="abi")


def render_userland_implementation(stream: CodeStream, abi: ABI_Definition):
    root_container = abi.root_container

    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!

const std = @import("std");
const abi = @import("abi");

""")

    all_error_sets = ErrorSetMapper()

    def emit_impl(func: Function, ns: tuple[str, ...]):
        gen_params: list[GenParam] = list()

        print("emit", func.name)
        for _name, _annotation, _abi, _natives in func.params:
            # _wrapper is required to "drop" the four parameters
            # from the local scope and move them into a nested one,
            # so the two closures can actually capture them safely
            def _wrapper(name, annotation, abi, natives):
                invocation_args: list[str] = list()
                if annotation.is_slice:
                    assert len(natives) == 2
                    (ptr_p, len_p) = natives

                    if annotation.is_optional:
                        if annotation.is_out:
                            invocation_args.append(f"&{name}__slice_ptr")
                            invocation_args.append(f"&{name}__slice_len")
                        else:
                            invocation_args.append(
                                f"if ({name}) |__slice| __slice.ptr else null"
                            )
                            invocation_args.append(
                                f"if ({name}) |__slice| __slice.len else 0"
                            )
                    else:  # not optional
                        if annotation.is_out:
                            invocation_args.append(f"&{name}__slice_ptr")
                            invocation_args.append(f"&{name}__slice_len")
                        else:
                            invocation_args.append(f"{name}.ptr")
                            invocation_args.append(f"{name}.len")
                    assert len(invocation_args) == 2
                else:
                    assert len(natives) == 1
                    invocation_args.append(natives[0].name)

                slice_name = f"{name}__slice"
                ptr_name = f"{slice_name}_ptr"
                len_name = f"{slice_name}_len"

                def handle_before_call():
                    if not annotation.is_slice:
                        return
                    if not annotation.is_out:
                        return

                    # out_slices.append((name, , annotation.is_optional))
                    stream.write(f"var {slice_name}_ptr: ")
                    assert isinstance(natives[0].type, PointerType)
                    render_type(stream, natives[0].type.inner, abi_namespace="abi")
                    if isinstance(natives[0].type.inner, OptionalType):
                        stream.writeln(
                            f" = if({abi.name}.*) |__slice| __slice.ptr else null;"
                        )
                    else:
                        stream.writeln(f" = {name}.ptr;")

                    if annotation.is_optional:
                        stream.writeln(
                            f"var {slice_name}_len: usize = if({abi.name}.*) |__slice| __slice.len else 0;"
                        )
                    else:
                        stream.writeln(f"var {slice_name}_len: usize = {abi.name}.len;")

                def handle_before_return():
                    if not annotation.is_slice:
                        return
                    if not annotation.is_out:
                        return
                    if annotation.is_optional:
                        stream.writeln(
                            f"{name}.* = if ({ptr_name}) |__ptr| __ptr[0..{len_name}] else null;"
                        )
                    else:
                        stream.writeln(f"{name}.* = {ptr_name}[0..{len_name}];")

                gen_params.append(
                    GenParam(
                        signature=[abi],
                        invocation=invocation_args,
                        before_call=handle_before_call,
                        before_return=handle_before_return,
                    )
                )

            _wrapper(_name, _annotation, _abi, _natives)

        signature_params = [p for gp in gen_params for p in gp.signature]
        invocation_params = [p for gp in gen_params for p in gp.invocation]

        abi_name = ".".join(("abi", *ns, func.name))
        stream.write(f'pub fn @"{func.name}"(')
        render_parameter_list(stream, signature_params)
        stream.write(") ")

        if isinstance(func.abi_return_type, ErrorUnion):
            error_union: ErrorUnion = func.abi_return_type
            stream.write("error{ ")
            stream.write(", ".join((*error_union.error.errors, "Unexpected")))
            stream.write(" }!")
            render_type(stream, error_union.result, abi_namespace="abi")

            invocation_params.append("&__result")

            @contextmanager
            def handle_call():
                stream.write("var __result: ")
                render_type(stream, error_union.result, abi_namespace="abi")
                stream.writeln(" = undefined;")

                stream.write("const __error_code: ")
                stream.write(all_error_sets.get_native_error_type(error_union.error))
                stream.write(" = ")

                yield

                stream.writeln("return if (__error_code != .ok)")
                with stream.indent():
                    stream.writeln(
                        f"{all_error_sets.get_native_to_zig_mapper(error_union.error)}(__error_code)"
                    )
                stream.writeln("else")
                with stream.indent():
                    stream.writeln("__result;")
        elif isinstance(func.native_return_type, ErrorSet):
            error_set: ErrorSet = func.native_return_type
            stream.write("error{ ")
            stream.write(", ".join((*error_set.errors, "Unexpected")))
            stream.write(" }!void")

            @contextmanager
            def handle_call():
                stream.write("const __error_value = ")

                yield

                stream.writeln("if (__error_value != .ok)")
                with stream.indent():
                    stream.writeln(
                        f"return {all_error_sets.get_native_to_zig_mapper(error_set)}(__error_value);"
                    )
        else:

            @contextmanager
            def handle_call():
                stream.write("const __result = ")
                yield
                stream.writeln("return __result;")

            render_type(stream, func.native_return_type, abi_namespace="abi")

        stream.writeln(" {")

        with stream.indent():
            for gp in gen_params:
                if gp.before_call is not None:
                    gp.before_call()

            with handle_call():
                stream.writeln(f"{abi_name}(")
                with stream.indent():
                    for arg in invocation_params:
                        stream.writeln(f"{arg},")
                stream.writeln(f");")

                for gp in gen_params:
                    if gp.before_return is not None:
                        gp.before_return()

        stream.writeln("}")
        stream.writeln()

    def recursive_render(
        decls: list[Declaration], ns_prefix: tuple[str, ...] = tuple()
    ):
        for decl in decls:
            if isinstance(decl, Namespace):
                stream.writeln(f"pub const {decl.name} = struct {{")
                with stream.indent():
                    recursive_render(decl.decls, (*ns_prefix, decl.name))
                stream.writeln("};")
                stream.writeln()
            elif isinstance(decl, Function):
                emit_impl(decl, ns_prefix)
            elif (
                isinstance(decl, ErrorSet)
                or isinstance(decl, AsyncOp)
                or isinstance(decl, SystemResource)
            ):
                pass
            else:
                panic("unexpected", decl)

    recursive_render(root_container.decls)

    stream.writeln()

    all_error_sets.render_native_to_zig_mappers(stream)


def render_stubs_implementation(stream, abi: ABI_Definition):
    stream.write("""//!
//! THIS CODE WAS AUTOGENERATED!
//!
const std = @import("std");
const abi = @import("abi");

fn __syscall_stub() callconv(.C) void {}

""")

    def emit_impl(func: Function, ns: list[str]):
        emit_name = "_".join(("ashet", *ns, func.name))

        stream.writeln("@export(__syscall_stub, std.builtin.ExportOptions{")
        with stream.indent():
            stream.writeln(f'.name = "{emit_name}",')
        stream.writeln("});")

    stream.writeln("comptime {")
    with stream.indent():
        foreach(abi.root_container.decls, Function, func=emit_impl)
    stream.writeln("}")

    stream.writeln()


class Renderer(StrEnum):
    definition = "definition"
    kernel = "kernel"
    userland = "userland"
    stubs = "stubs"


def _create_enumeration(
    declarations,
    ElementType: type,
):
    numbers: dict[int, AsyncOp] = dict()

    def allocate_iop_num(iop: AsyncOp, ns: list[str]):
        index = len(numbers) + 1
        name = "_".join([*ns, caseconverter.snakecase(iop.name)])
        iop.key.value = name
        iop.number.value = index
        numbers[index] = iop
        # print("assign", name, iop.number.value, iop.key.value)

    foreach(declarations, ElementType, allocate_iop_num)

    if len(numbers) > 1:
        all_iops = [iop.key.value for iop in numbers.values()]
        # print(all_iops)
        iop_prefix = os.path.commonprefix(all_iops)
        # print("common prefix: ", iop_prefix)
        for iop in numbers.values():
            # old = iop.key.value
            iop.key.value = iop.key.value.removeprefix(iop_prefix)
            # print(iop.name,repr(old), repr(iop.key.value))

    return list(numbers.values())


def main():
    global WITH_LINKNAME

    cli_parser = ArgumentParser()

    cli_parser.add_argument("--output", type=Path, required=False)
    cli_parser.add_argument(
        "--mode", type=Renderer, required=False, default=Renderer.definition
    )
    cli_parser.add_argument("--use-linkname", action="store_true", required=False)
    cli_parser.add_argument("--zig-exe", type=Path, required=False)
    cli_parser.add_argument("abi", type=Path)

    cli = cli_parser.parse_args()

    output_path: Path | None = cli.output
    abi_path: Path = cli.abi
    render_mode: Renderer = cli.mode
    WITH_LINKNAME = cli.use_linkname
    zig_exe: Path | None = Path(cli.zig_exe) if cli.zig_exe else None

    grammar_source = GRAMMAR_PATH.read_text()
    zig_parser = Lark(grammar_source, start="toplevel")

    source_code = abi_path.read_text()

    transformer = ZigCodeTransformer()

    parse_tree = zig_parser.parse(source_code)

    root_container: TopLevelCode = transformer.transform(parse_tree)

    errors = ErrorAllocation()
    for decl in root_container.decls:
        errors.collect(decl)

    iop_list = _create_enumeration(
        root_container.decls,
        AsyncOp,
    )

    syscall_list = _create_enumeration(
        root_container.decls,
        Function,
    )

    foreach(root_container.decls, Function, func=assert_legal_extern_fn)

    def _set_ns_name(decl: Declaration, ns: list[str]):
        decl.full_qualified_name.value = ".".join((*ns, decl.name))

    foreach(root_container.decls, Declaration, func=_set_ns_name)

    sys_resources: list[str] = list()

    def collect_src(src: SystemResource, ns: list[str]):
        name = ".".join([*ns, src.name])
        sys_resources.append(name)

    foreach(root_container.decls, SystemResource, collect_src)

    abi = ABI_Definition(
        root_container=root_container,
        errors=errors,
        sys_resources=sys_resources,
        iops=iop_list,
        syscalls=syscall_list,
    )

    renderer = {
        Renderer.definition: render_abi_definition,
        Renderer.kernel: render_kernel_implementation,
        Renderer.userland: render_userland_implementation,
        Renderer.stubs: render_stubs_implementation,
    }[render_mode]

    generated_code: str
    with io.StringIO() as f:
        renderer(stream=CodeStream(f), abi=abi)
        generated_code = f.getvalue()

    if zig_exe is not None:
        fmt_result = subprocess.run(
            args=[
                zig_exe,
                "fmt",
                "--stdin",
                "--ast-check",
            ],
            input=generated_code.encode("utf-8"),
            stdout=subprocess.PIPE,
            check=False,
        )
        if fmt_result.returncode == 0:
            generated_code = fmt_result.stdout.decode("utf-8")

    if output_path is not None:
        output_path.write_text(generated_code, encoding="utf-8")
    else:
        sys.stdout.write(generated_code)


if __name__ == "__main__":
    main()
