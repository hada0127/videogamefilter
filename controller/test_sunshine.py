"""Exercise the actual C++ sender against a Unix socket (macOS build host only)."""
import json
import pathlib
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest

@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('clang++'), 'macOS compiler required')
class SunshineTests(unittest.TestCase):
    def test_held_input_liveness_is_per_pad_and_releases_on_loss(self):
        with tempfile.TemporaryDirectory(prefix='vgf-test-', dir='/tmp') as d:
            root = pathlib.Path(d)
            source = root/'test.cpp'
            source.write_text('''#include "vgf_input.h"
int main(int argc, char **argv) {
  vgf::Input input(argv[1]);
  if (!input.allocate(0) || !input.allocate(1)) return 2;
  input.update(0,4096,0,0,-32768,32767,0,0);
  input.update(1,8192,0,0,0,0,0,0);
  for (int i=0;i<8;++i) {
    input.alive(0);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  input.alive(1); // A recovered ping must not resurrect its expired button.
  std::this_thread::sleep_for(std::chrono::milliseconds(500));
  input.release(0);input.release(1);
}
''')
            subprocess.run(['clang++','-std=c++17','-I',str(pathlib.Path(__file__).parent/'sunshine'),str(source),'-o',str(root/'test')],check=True,capture_output=True)
            with socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM) as receiver:
                path = str(root/'input.sock'); receiver.bind(path); receiver.settimeout(3)
                process = subprocess.Popen([str(root/'test'),path])
                events=[];start=time.monotonic()
                try:
                    while True:
                        packet=json.loads(receiver.recv(2048));events.append((time.monotonic()-start,packet))
                        if packet['id']==1 and not packet['active']:break
                    self.assertEqual(process.wait(timeout=3),0)
                finally:
                    if process.poll() is None:process.kill();process.wait()
                self.assertTrue(any(.5<t<.8 and p['id']==0 and p['buttons']==4096 for t,p in events))
                self.assertTrue(any(.5<t<.8 and p['id']==1 and p['buttons']==0 for t,p in events))
                self.assertTrue(any(t>1.1 and p['id']==0 and p['buttons']==0 for t,p in events))
                self.assertTrue(any(p['lx']==-32768 and p['ly']==32767 for _,p in events))
                self.assertTrue(all(p['buttons']==0 for t,p in events if t>.85 and p['id']==1))
                self.assertFalse(events[-1][1]['active'])
