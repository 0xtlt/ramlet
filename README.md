# Ramlet

Petit moniteur natif de mémoire unifiée pour la barre des menus de macOS, construit en Rust avec une fine passerelle AppKit.

## Ce qu’il affiche

- la mémoire physique utilisée sur la mémoire unifiée totale ;
- les applications regroupées avec tous leurs sous-processus ;
- l’icône macOS de chaque application ;
- une largeur fixe dans la barre des menus, même lorsque les chiffres changent ;
- une icône `memorychip` en contour dans la barre des menus ;
- un toggle persistant pour inclure ou exclure les caches et la mémoire non attribuée du total affiché ;
- la mémoire compressée, la mémoire système câblée et le swap ;
- une actualisation automatique toutes les 15 secondes et à l’ouverture du menu.

La mesure par application utilise l’empreinte physique publiée par macOS (`proc_pid_rusage`). Les allocations GPU partagent le même pool de mémoire sur Apple Silicon, mais macOS ne permet pas d’attribuer exhaustivement toute la mémoire GPU à chaque application. Ramlet l’indique donc comme « GPU inclus lorsqu’attribuable ».

## Compiler

Prérequis : macOS 13 ou plus récent, Rust et les outils de ligne de commande Xcode.

```bash
cargo test
cargo build --release
./target/release/ramlet --snapshot
./target/release/ramlet --self-test-ui
./scripts/package-macos.sh
```

L’application et l’archive ZIP sont produites dans `dist/`. Le bundle est signé localement de manière ad hoc ; il n’est ni signé avec un certificat Apple Developer ni notarized.
