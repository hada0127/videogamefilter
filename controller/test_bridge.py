import unittest
import bridge
class InputTests(unittest.TestCase):
    def test_axes(self):
        self.assertEqual(bridge.decode_input('{"type":"input","buttons":["A"],"lx":-1,"ry":0.35}'), (["A"],[-100,0,0,35]))
    def test_bad_inputs(self):
        for line in ['null','[]','{}','{"type":"input","buttons":["BAD"]}','{"type":"input","lx":true}','{"type":"input","lx":NaN}','{"type":"input","lx":1.01}']:
            with self.subTest(line=line), self.assertRaises(ValueError): bridge.decode_input(line)
    def test_neutral(self):
        self.assertEqual(bridge.decode_input('{"type":"input"}'), ([],[0,0,0,0]))

class PacketTests(unittest.TestCase):
    def test_stick_press_and_axis(self):
        class FakeNX:
            def create_input_packet(self):
                return {'A': False, 'L_STICK': {'PRESSED': False, 'X_VALUE': 0, 'Y_VALUE': 0}, 'R_STICK': {'PRESSED': False, 'X_VALUE': 0, 'Y_VALUE': 0}}
        packet = bridge.packet_for(FakeNX(), (['A', 'L_STICK_PRESS', 'R_STICK_PRESS'], [25,-40,60,-80]))
        self.assertTrue(packet['A'])
        self.assertTrue(packet['L_STICK']['PRESSED'])
        self.assertTrue(packet['R_STICK']['PRESSED'])
        self.assertEqual(packet['R_STICK']['Y_VALUE'], -80)
        self.assertNotIn('L_STICK_PRESS', packet)


class UDPTests(unittest.TestCase):
    def packet(self, seq, key=b'k'*32):
        import hmac, hashlib
        raw = seq.to_bytes(8, 'big') + b'{"type":"input","buttons":["A"]}'
        return raw + hmac.new(key, raw, hashlib.sha256).digest()
    def test_authentication_and_newest_sequence(self):
        seq, decoded = bridge.decode_datagram(self.packet(2), b'k'*32, 1)
        self.assertEqual(seq, 2)
        self.assertEqual(decoded[0], ['A'])
        for seq in (1, 2):
            with self.assertRaises(ValueError): bridge.decode_datagram(self.packet(seq), b'k'*32, 2)
    def test_reject_bad_authentication_and_size(self):
        for data in (self.packet(3, b'x'*32), b'', b'x'*2049, self.packet(3)[:-1]+b'!'):
            with self.assertRaises(ValueError): bridge.decode_datagram(data, b'k'*32, 0)
    def test_cross_language_vector(self):
        data = bytes.fromhex("000000000000002a7b2274797065223a22696e707574222c22627574746f6e73223a5b2241225d2c226c78223a302e357d1ee60064e3838073b555b5f5c66e1f5bb1c3633f60aab4fbe30192d9209887b4")
        self.assertEqual(bridge.decode_datagram(data, bytes(range(32)), 41), (42, (['A'], [50,0,0,0])))

if __name__ == '__main__': unittest.main()
