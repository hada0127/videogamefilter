import json
from pathlib import Path
import tempfile
import unittest
import service

class RegistrationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / 'device.json'
        self.path.write_text(json.dumps({'id':'device-id', 'secret':'ab'*32, 'pin_hash':service.pin_hash('device-id','123456'), 'paired':False}))
        self.registry = service.Registry(self.path)
        self.client = '00000000-0000-0000-0000-000000000001'
    def tearDown(self): self.directory.cleanup()
    def test_enrollment_retry_and_persistent_token(self):
        request = {'client':self.client,'pin':'123456'}
        token = self.registry.authenticate(request)
        self.assertEqual(self.registry.authenticate(request), token)
        self.registry.confirm(self.client)
        with self.assertRaises(ValueError): self.registry.authenticate(request)
        restarted = service.Registry(self.path)
        self.assertIsNone(restarted.authenticate({'client':self.client,'token':token}))
        self.assertNotIn('pin_hash', json.loads(self.path.read_text()))
    def test_lost_confirmation_recovers_with_saved_token(self):
        token = self.registry.authenticate({'client':self.client,'pin':'123456'})
        self.assertIsNone(service.Registry(self.path).authenticate({'client':self.client,'token':token}))
        self.assertTrue(json.loads(self.path.read_text())['paired'])
    def test_other_client_cannot_take_pending_registration(self):
        self.registry.authenticate({'client':self.client,'pin':'123456'})
        with self.assertRaises(ValueError): self.registry.authenticate({'client':'00000000-0000-0000-0000-000000000002','pin':'123456'})
    def test_wrong_pin_rate_limit(self):
        for _ in range(5):
            with self.assertRaises(ValueError): self.registry.authenticate({'client':self.client,'pin':'000000'})
        with self.assertRaisesRegex(ValueError,'1분'): self.registry.authenticate({'client':self.client,'pin':'123456'})

if __name__ == '__main__': unittest.main()

class IdentityInstallTests(unittest.TestCase):
    def test_same_identity_preserves_pairing_and_new_identity_replaces(self):
        import install_identity
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder)/'source', Path(folder)/'target'
            source.mkdir()
            first = {'id':'00000000-0000-0000-0000-000000000001','paired':False}
            (source/'device.json').write_text(json.dumps(first))
            for name in ['server.key','server.crt']: (source/name).write_text('first')
            self.assertTrue(install_identity.install_identity(source,target))
            paired = dict(first, paired=True, client={'hash':'stored'})
            (target/'device.json').write_text(json.dumps(paired))
            self.assertFalse(install_identity.install_identity(source,target))
            self.assertEqual(json.loads((target/'device.json').read_text()), paired)
            (source/'device.json').write_text(json.dumps(dict(first,id='00000000-0000-0000-0000-000000000002')))
            (source/'server.key').write_text('second')
            self.assertTrue(install_identity.install_identity(source,target))
            self.assertEqual((target/'server.key').read_text(),'second')
            self.assertFalse(json.loads((target/'device.json').read_text())['paired'])
