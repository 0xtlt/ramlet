#![cfg(target_os = "macos")]

use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::mem::{MaybeUninit, size_of};
use std::path::Path;
use std::ptr;

const RUSAGE_INFO_V2: c_int = 2;
const HOST_VM_INFO64: c_int = 4;
const PROC_PIDPATHINFO_MAXSIZE: usize = 4096;

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct RusageInfoV2 {
    uuid: [u8; 16],
    user_time: u64,
    system_time: u64,
    pkg_idle_wkups: u64,
    interrupt_wkups: u64,
    pageins: u64,
    wired_size: u64,
    resident_size: u64,
    phys_footprint: u64,
    proc_start_abstime: u64,
    proc_exit_abstime: u64,
    child_user_time: u64,
    child_system_time: u64,
    child_pkg_idle_wkups: u64,
    child_interrupt_wkups: u64,
    child_pageins: u64,
    child_elapsed_abstime: u64,
    diskio_bytesread: u64,
    diskio_byteswritten: u64,
}

#[repr(C, align(8))]
#[derive(Clone, Copy, Default)]
struct VmStatistics64 {
    free_count: u32,
    active_count: u32,
    inactive_count: u32,
    wire_count: u32,
    zero_fill_count: u64,
    reactivations: u64,
    pageins: u64,
    pageouts: u64,
    faults: u64,
    cow_faults: u64,
    lookups: u64,
    hits: u64,
    purges: u64,
    purgeable_count: u32,
    speculative_count: u32,
    decompressions: u64,
    compressions: u64,
    swapins: u64,
    swapouts: u64,
    compressor_page_count: u32,
    throttled_count: u32,
    external_page_count: u32,
    internal_page_count: u32,
    total_uncompressed_pages_in_compressor: u64,
    swapped_count: u64,
    total_tag_storage_pages: u64,
    nontag_pageable_tag_storage_pages: u64,
    nontag_wired_tag_storage_pages: u64,
    free_tag_storage_pages: u64,
    tag_storing_tag_storage_pages: u64,
    total_tagged_pages: u64,
    resident_tagged_pages: u64,
    compressed_tagged_pages: u64,
    tagged_compressions: u64,
    tagged_decompressions: u64,
    compressed_tag_storage_bytes: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct SwapUsage {
    total: u64,
    avail: u64,
    used: u64,
    page_size: u32,
    encrypted: c_int,
}

unsafe extern "C" {
    fn proc_listallpids(buffer: *mut c_void, buffersize: c_int) -> c_int;
    fn proc_pidpath(pid: c_int, buffer: *mut c_void, buffersize: u32) -> c_int;
    fn proc_pid_rusage(pid: c_int, flavor: c_int, buffer: *mut c_void) -> c_int;

    fn mach_host_self() -> u32;
    fn host_page_size(host: u32, page_size: *mut u32) -> c_int;
    fn host_statistics64(host: u32, flavor: c_int, host_info: *mut c_int, count: *mut u32)
    -> c_int;
    fn sysctlbyname(
        name: *const c_char,
        old_value: *mut c_void,
        old_len: *mut usize,
        new_value: *mut c_void,
        new_len: usize,
    ) -> c_int;

    fn ramlet_run() -> c_int;
    fn ramlet_ui_self_test() -> c_int;
}

#[derive(Debug, Clone)]
struct AppUsage {
    name: String,
    bundle_path: String,
    bytes: u64,
    process_count: usize,
}

#[derive(Debug, Clone, Default)]
struct Snapshot {
    total_bytes: u64,
    used_bytes: u64,
    compressed_bytes: u64,
    wired_bytes: u64,
    swap_bytes: u64,
    app_footprint_bytes: u64,
    service_bytes: u64,
    process_count: usize,
    inaccessible_count: usize,
    apps: Vec<AppUsage>,
}

fn sysctl_value<T: Copy + Default>(key: &CStr) -> Option<T> {
    let mut value = MaybeUninit::<T>::zeroed();
    let mut length = size_of::<T>();
    let result = unsafe {
        sysctlbyname(
            key.as_ptr(),
            value.as_mut_ptr().cast(),
            &mut length,
            ptr::null_mut(),
            0,
        )
    };

    (result == 0 && length >= size_of::<T>()).then(|| unsafe { value.assume_init() })
}

fn virtual_memory() -> Option<(u64, u64, u64, u64)> {
    let host = unsafe { mach_host_self() };
    let mut page_size = 0_u32;
    if unsafe { host_page_size(host, &mut page_size) } != 0 {
        return None;
    }

    let mut stats = VmStatistics64::default();
    let mut count = (size_of::<VmStatistics64>() / size_of::<c_int>()) as u32;
    let result = unsafe {
        host_statistics64(
            host,
            HOST_VM_INFO64,
            (&mut stats as *mut VmStatistics64).cast(),
            &mut count,
        )
    };
    if result != 0 {
        return None;
    }

    let page = u64::from(page_size);
    let free = u64::from(stats.free_count).saturating_mul(page);
    let compressed = u64::from(stats.compressor_page_count).saturating_mul(page);
    let wired = u64::from(stats.wire_count).saturating_mul(page);
    Some((free, compressed, wired, page))
}

fn list_pids() -> Vec<c_int> {
    let estimated = unsafe { proc_listallpids(ptr::null_mut(), 0) };
    let capacity = if estimated > 0 {
        estimated as usize + 256
    } else {
        4096
    };
    let mut pids = vec![0_i32; capacity];
    let count = unsafe {
        proc_listallpids(
            pids.as_mut_ptr().cast(),
            (pids.len() * size_of::<c_int>()) as c_int,
        )
    };
    if count <= 0 {
        return Vec::new();
    }

    pids.truncate((count as usize).min(pids.len()));
    pids.retain(|pid| *pid > 0);
    pids
}

fn process_path(pid: c_int) -> Option<String> {
    let mut buffer = vec![0_u8; PROC_PIDPATHINFO_MAXSIZE];
    let length = unsafe {
        proc_pidpath(
            pid,
            buffer.as_mut_ptr().cast(),
            PROC_PIDPATHINFO_MAXSIZE as u32,
        )
    };
    if length <= 0 {
        return None;
    }

    let path = unsafe { CStr::from_ptr(buffer.as_ptr().cast()) };
    Some(path.to_string_lossy().into_owned())
}

fn process_footprint(pid: c_int) -> Option<u64> {
    let mut usage = RusageInfoV2::default();
    let result = unsafe {
        proc_pid_rusage(
            pid,
            RUSAGE_INFO_V2,
            (&mut usage as *mut RusageInfoV2).cast(),
        )
    };
    (result == 0).then_some(usage.phys_footprint)
}

fn outer_app_bundle(path: &str) -> Option<&str> {
    let app_end = path
        .find(".app/")
        .map(|position| position + 4)
        .or_else(|| path.ends_with(".app").then_some(path.len()))?;
    let bundle = &path[..app_end];

    let is_user_facing = bundle.contains("/Applications/")
        || (!bundle.starts_with("/System/Library/")
            && !bundle.starts_with("/Library/Apple/System/Library/"));
    is_user_facing.then_some(bundle)
}

fn app_name(bundle_path: &str) -> String {
    Path::new(bundle_path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("Application")
        .strip_suffix(".app")
        .unwrap_or("Application")
        .to_owned()
}

fn collect_snapshot() -> Snapshot {
    let total_key = c"hw.memsize";
    let swap_key = c"vm.swapusage";
    let total_bytes = sysctl_value::<u64>(total_key).unwrap_or_default();
    let swap_bytes = sysctl_value::<SwapUsage>(swap_key)
        .map(|usage| usage.used)
        .unwrap_or_default();
    let (free_bytes, compressed_bytes, wired_bytes, _) = virtual_memory().unwrap_or_default();
    let used_bytes = total_bytes.saturating_sub(free_bytes);

    let mut grouped: HashMap<String, AppUsage> = HashMap::new();
    let mut service_bytes = 0_u64;
    let mut inaccessible_count = 0_usize;
    let pids = list_pids();

    for pid in &pids {
        let Some(bytes) = process_footprint(*pid) else {
            inaccessible_count += 1;
            continue;
        };
        let Some(path) = process_path(*pid) else {
            service_bytes = service_bytes.saturating_add(bytes);
            continue;
        };

        if let Some(bundle_path) = outer_app_bundle(&path) {
            let entry = grouped
                .entry(bundle_path.to_owned())
                .or_insert_with(|| AppUsage {
                    name: app_name(bundle_path),
                    bundle_path: bundle_path.to_owned(),
                    bytes: 0,
                    process_count: 0,
                });
            entry.bytes = entry.bytes.saturating_add(bytes);
            entry.process_count += 1;
        } else {
            service_bytes = service_bytes.saturating_add(bytes);
        }
    }

    let mut apps: Vec<AppUsage> = grouped.into_values().collect();
    apps.sort_by(|left, right| {
        right
            .bytes
            .cmp(&left.bytes)
            .then_with(|| left.name.cmp(&right.name))
    });
    let app_footprint_bytes = apps.iter().map(|app| app.bytes).sum();

    Snapshot {
        total_bytes,
        used_bytes,
        compressed_bytes,
        wired_bytes,
        swap_bytes,
        app_footprint_bytes,
        service_bytes,
        process_count: pids.len(),
        inaccessible_count,
        apps,
    }
}

fn clean_field(value: &str) -> String {
    value.replace(['\t', '\n', '\r'], " ")
}

fn snapshot_tsv(snapshot: &Snapshot) -> String {
    let mut output = format!(
        "META\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
        snapshot.used_bytes,
        snapshot.total_bytes,
        snapshot.compressed_bytes,
        snapshot.wired_bytes,
        snapshot.swap_bytes,
        snapshot.app_footprint_bytes,
        snapshot.service_bytes,
        snapshot.process_count,
        snapshot.inaccessible_count,
    );
    for app in &snapshot.apps {
        output.push_str(&format!(
            "APP\t{}\t{}\t{}\t{}\n",
            app.bytes,
            app.process_count,
            clean_field(&app.bundle_path),
            clean_field(&app.name),
        ));
    }
    output
}

#[unsafe(no_mangle)]
pub extern "C" fn ramlet_snapshot_tsv() -> *mut c_char {
    let payload = snapshot_tsv(&collect_snapshot());
    CString::new(payload)
        .expect("snapshot cannot contain NUL bytes")
        .into_raw()
}

/// Frees a C string returned by [`ramlet_snapshot_tsv`].
///
/// # Safety
///
/// `value` must be null or a pointer previously returned by
/// [`ramlet_snapshot_tsv`] and not already freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ramlet_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    if arguments.iter().any(|argument| argument == "--snapshot") {
        print!("{}", snapshot_tsv(&collect_snapshot()));
        return;
    }
    if arguments
        .iter()
        .any(|argument| argument == "--self-test-ui")
    {
        let result = unsafe { ramlet_ui_self_test() };
        if result == 0 {
            println!("Ramlet UI self-test: OK");
        } else {
            eprintln!("Ramlet UI self-test failed with code {result}");
        }
        std::process::exit(result);
    }

    let exit_code = unsafe { ramlet_run() };
    std::process::exit(exit_code);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn groups_nested_helpers_under_the_outer_application() {
        let path = "/Applications/Dia.app/Contents/Frameworks/ArcCore.framework/Helpers/Browser Helper (Renderer).app/Contents/MacOS/Browser Helper (Renderer)";
        assert_eq!(outer_app_bundle(path), Some("/Applications/Dia.app"));
    }

    #[test]
    fn keeps_system_applications_but_not_core_services() {
        assert_eq!(
            outer_app_bundle(
                "/System/Applications/System Settings.app/Contents/MacOS/System Settings"
            ),
            Some("/System/Applications/System Settings.app")
        );
        assert_eq!(
            outer_app_bundle("/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"),
            None
        );
    }

    #[test]
    fn snapshot_payload_is_tabular_and_safe() {
        let snapshot = Snapshot {
            total_bytes: 48,
            used_bytes: 42,
            apps: vec![AppUsage {
                name: "App\nName".into(),
                bundle_path: "/Applications/App.app".into(),
                bytes: 12,
                process_count: 3,
            }],
            ..Snapshot::default()
        };
        let payload = snapshot_tsv(&snapshot);
        assert!(payload.starts_with("META\t42\t48\t"));
        assert!(payload.contains("APP\t12\t3\t/Applications/App.app\tApp Name\n"));
    }

    fn strings_keys(path: &Path) -> std::collections::BTreeSet<String> {
        let text = std::fs::read_to_string(path)
            .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
        let mut keys = std::collections::BTreeSet::new();
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with("/*") || line.starts_with("//") {
                continue;
            }
            let Some(rest) = line.strip_prefix('"') else {
                continue;
            };
            let mut key = String::new();
            let mut chars = rest.chars();
            while let Some(ch) = chars.next() {
                if ch == '\\' {
                    if let Some(escaped) = chars.next() {
                        key.push(escaped);
                    }
                    continue;
                }
                if ch == '"' {
                    break;
                }
                key.push(ch);
            }
            keys.insert(key);
        }
        keys
    }

    fn objc_localized_keys(source: &str) -> std::collections::BTreeSet<String> {
        let mut keys = std::collections::BTreeSet::new();
        let mut rest = source;
        let marker = "RamletLocalizedString(@\"";
        while let Some(start) = rest.find(marker) {
            rest = &rest[start + marker.len()..];
            if let Some(end) = rest.find('"') {
                keys.insert(rest[..end].to_string());
                rest = &rest[end + 1..];
            } else {
                break;
            }
        }
        keys
    }

    #[test]
    fn localization_tables_match_and_cover_the_ui() {
        let macos = Path::new(env!("CARGO_MANIFEST_DIR")).join("macos");
        let en = strings_keys(&macos.join("en.lproj/Localizable.strings"));
        let fr = strings_keys(&macos.join("fr.lproj/Localizable.strings"));
        let es = strings_keys(&macos.join("es.lproj/Localizable.strings"));
        assert_eq!(en, fr, "French keys should match English");
        assert_eq!(en, es, "Spanish keys should match English");
        assert!(!en.is_empty(), "English string table should not be empty");

        let menubar =
            std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("src/menubar.m"))
                .expect("menubar.m should be readable");
        let used = objc_localized_keys(&menubar);
        assert!(
            !used.is_empty(),
            "menubar.m should look up localized strings"
        );
        let missing: Vec<_> = used.difference(&en).cloned().collect();
        assert!(
            missing.is_empty(),
            "string tables are missing keys used by the UI: {missing:?}"
        );
        let unused: Vec<_> = en.difference(&used).cloned().collect();
        assert!(
            unused.is_empty(),
            "string tables contain unused keys: {unused:?}"
        );
    }
}
