"""Locate an existing simulator; never download or install software."""
from __future__ import annotations
import os
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]

def executable(folder: Path, name: str) -> Path | None:
    for candidate in (folder/(name+'.exe'), folder/name):
        if candidate.is_file():
            return candidate.resolve()
    return None

def locate_icarus(explicit: Path | None = None) -> Path:
    if explicit is not None:
        folders = [Path(explicit)]
    elif os.environ.get('IVERILOG_BIN'):
        folders = [Path(os.environ['IVERILOG_BIN'])]
    else:
        folders = [ROOT/'.tools/iverilog/mingw64/bin']
        installed = shutil.which('iverilog')
        if installed:
            folders.append(Path(installed).parent)
    for folder in folders:
        if executable(folder, 'iverilog') and executable(folder, 'vvp'):
            return folder.resolve()
    raise SystemExit('Icarus not found. Use an existing installation on PATH, '
                     'set IVERILOG_BIN, or pass --iverilog-bin /path/to/bin. '
                     'The private .tools runtime is not included in Git.')

def prepare_icarus(build: Path, explicit: Path | None = None) -> tuple[Path, Path]:
    folder = locate_icarus(explicit)
    if os.name == 'nt' and not str(folder).isascii():
        # Preserve bin + lib/ivl + DLL layout; support Unicode Windows workspaces.
        prefix = build/'toolchain/icarus'
        shutil.copytree(folder.parent, prefix)
        folder = prefix/folder.name
    return executable(folder, 'iverilog'), executable(folder, 'vvp')
