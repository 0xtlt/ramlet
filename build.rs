use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=src/menubar.m");
    println!("cargo:rerun-if-changed=macos/en.lproj/Localizable.strings");
    println!("cargo:rerun-if-changed=macos/fr.lproj/Localizable.strings");
    println!("cargo:rerun-if-changed=macos/es.lproj/Localizable.strings");

    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is set by Cargo"));
    let object = out_dir.join("menubar.o");

    let clang_arch = match env::var("CARGO_CFG_TARGET_ARCH").as_deref() {
        Ok("x86_64") => "x86_64",
        Ok("aarch64") => "arm64",
        other => panic!("unsupported macOS target arch: {other:?}"),
    };

    let mut command = Command::new("xcrun");
    command.args([
        "clang",
        "-arch",
        clang_arch,
        "-fobjc-arc",
        "-fmodules",
        "-fblocks",
        "-Wno-format-nonliteral",
        "-mmacosx-version-min=13.0",
    ]);

    if env::var("PROFILE").as_deref() == Ok("debug") {
        let resources = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"))
            .join("macos");
        command.arg(format!(
            "-DRAMLET_DEV_RESOURCES=\"{}\"",
            resources.display()
        ));
    }

    let status = command
        .args(["-c", "src/menubar.m", "-o"])
        .arg(&object)
        .status()
        .expect("failed to run xcrun clang");

    assert!(status.success(), "Objective-C bridge compilation failed");

    println!("cargo:rustc-link-arg={}", object.display());
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=proc");
}
