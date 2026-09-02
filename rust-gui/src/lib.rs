//! The GUI crate only re-exports the pure core logic so the binary never
//! touches eframe/egui types when compiling headless tests (see `core/`).
pub use windows_split_pac_core::*;
