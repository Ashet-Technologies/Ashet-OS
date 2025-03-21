// {
//     const wikitool = b.addExecutable(.{
//         .name = "wikitool",
//         .root_source_file = b.path("tools/wikitool.zig"),
//         .target = b.graph.host,
//     });

//     wikitool.root_module.addImport("hypertext", mod_libhypertext);
//     wikitool.root_module.addImport("hyperdoc", mod_hyperdoc);
//     wikitool.root_module.addImport("args", mod_args);
//     wikitool.root_module.addImport("zigimg", mod_zigimg);
//     wikitool.root_module.addImport("ashet", mod_libashet);
//     wikitool.root_module.addImport("ashet-gui", mod_ashet_gui);

//     b.installArtifact(wikitool);
// }
