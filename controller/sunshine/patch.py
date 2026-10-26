#!/usr/bin/env python3
"""Apply the VGF controller backend to pinned Sunshine v2025.628.4510."""
import pathlib, shutil, subprocess, sys
root = pathlib.Path(sys.argv[1]).resolve()
revision = subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()
if revision != '65f14e1003f831e776c170621bd06d8292f65155':
    raise SystemExit('Expected Sunshine v2025.628.4510 (65f14e1)')
p = root/'src/platform/macos/input.cpp'
s = p.read_text()
if '#include "vgf_input.h"' not in s:
    s = '#include "vgf_input.h"\n' + s
    replacements = {
        'BOOST_LOG(info) << "alloc_gamepad: Gamepad not yet implemented for MacOS."sv;\n    return -1;': 'return vgf::input().allocate(id.globalIndex) ? 0 : -1;',
        'BOOST_LOG(info) << "free_gamepad: Gamepad not yet implemented for MacOS."sv;': 'vgf::input().release(nr);',
        'BOOST_LOG(info) << "gamepad: Gamepad not yet implemented for MacOS."sv;': 'const auto &s = gamepad_state;\n    vgf::input().update(nr, s.buttonFlags, s.lt, s.rt, s.lsX, s.lsY, s.rsX, s.rsY);',
    }
    for old,new in replacements.items():
        if s.count(old) != 1: raise SystemExit('Unexpected Sunshine source: '+old)
        s = s.replace(old,new)
    p.write_text(s)
shutil.copyfile(pathlib.Path(__file__).with_name('vgf_input.h'), p.with_name('vgf_input.h'))
# Refresh each client's own gamepads only on its authenticated periodic ping.
# Moonlight common's ControlStream.c sends periodic pings every 100 ms.
def insert_once(file, marker, old, new):
    text = file.read_text()
    if marker not in text:
        if text.count(old) != 1: raise SystemExit('Unexpected Sunshine source: '+str(file))
        file.write_text(text.replace(old,new))
insert_once(root/'src/input.h', 'void vgf_alive(', '  void print(void *input);',
    '#ifdef __APPLE__\n  void vgf_alive(std::shared_ptr<input_t> input);\n#endif\n  void print(void *input);')
insert_once(root/'src/input.cpp', 'vgf_input.h', '#include <cstdint>',
    '#include <cstdint>\n#ifdef __APPLE__\n#include "platform/macos/vgf_input.h"\n#endif')
insert_once(root/'src/input.cpp', 'void vgf_alive(', '  void passthrough(std::shared_ptr<input_t> &input, std::vector<std::uint8_t> &&input_data) {',
    '#ifdef __APPLE__\n  void vgf_alive(std::shared_ptr<input_t> input) {\n    task_pool.push([input] {\n      for (const auto &pad : input->gamepads) if (pad.id >= 0) vgf::input().alive(pad.id);\n    });\n  }\n#endif\n\n  void passthrough(std::shared_ptr<input_t> &input, std::vector<std::uint8_t> &&input_data) {')
insert_once(root/'src/stream.cpp', 'input::vgf_alive(',
    '      BOOST_LOG(verbose) << "type [IDX_PERIODIC_PING]"sv;',
    '      BOOST_LOG(verbose) << "type [IDX_PERIODIC_PING]"sv;\n#ifdef __APPLE__\n      input::vgf_alive(session->input);\n#endif')
insert_once(root/'src/platform/macos/input.cpp', 'supported_gamepad_t {"vgf", true',
    'supported_gamepad_t {"", false, "gamepads.macos_not_implemented"}',
    'supported_gamepad_t {"vgf", true, ""}')
print('VGF Sunshine local input backend installed')
