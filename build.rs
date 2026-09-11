use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=src/menubar.m");

    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is set by Cargo"));
    let object = out_dir.join("menubar.o");

    let status = Command::new("xcrun")
        .args([
            "clang",
            "-fobjc-arc",
            "-fmodules",
            "-fblocks",
            "-mmacosx-version-min=13.0",
            "-c",
            "src/menubar.m",
            "-o",
        ])
        .arg(&object)
        .status()
        .expect("failed to run xcrun clang");

    assert!(status.success(), "Objective-C bridge compilation failed");

    println!("cargo:rustc-link-arg={}", object.display());
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=proc");
}
