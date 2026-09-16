"""Exercise update detection and mutation boundaries without touching real jobs."""
import importlib.util
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('workaround', Path(__file__).parents[1] / 'istat_workaround.py')
workaround = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workaround)

class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.paths = dict(SOURCE=root/'source.app', DEST=root/'copy.app', AGENT=root/'job.plist',
                          STATE=root/'state', BACKUP=root/'backup.plist', MARKER=root/'marker.json')
        patcher = patch.multiple(workaround, **self.paths)
        patcher.start()
        self.addCleanup(patcher.stop)
        for app in (workaround.SOURCE, workaround.DEST):
            (app/workaround.EXECUTABLE).parent.mkdir(parents=True)
            (app/workaround.EXECUTABLE).write_bytes(b'signed executable')
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':workaround.LABEL,'CFBundleVersion':'1'}))
            (app/'Contents/_CodeSignature').mkdir()
            (app/'Contents/_CodeSignature/CodeResources').write_bytes(b'sealed resources v1')
        self.agent = dict(Label=workaround.LABEL, Program=str(workaround.DEST/workaround.EXECUTABLE),
                          MachServices={workaround.LABEL:True}, RunAtLoad=True, KeepAlive={'Crashed':True})
        workaround.AGENT.write_bytes(plistlib.dumps(self.agent))
        workaround.MARKER.write_text('{}')
        self.job = subprocess.CompletedProcess([],0,f'\tprogram = {workaround.DEST/workaround.EXECUTABLE}\n\tstate = running\n','')

    def test_current_copy_does_not_restart_helper(self):
        with patch.object(workaround,'run',return_value=self.job), patch.object(workaround,'install') as install:
            workaround.ensure()
            install.assert_not_called()

    def test_changed_executable_refreshes_copy(self):
        (workaround.SOURCE/workaround.EXECUTABLE).write_bytes(b'updated executable')
        with patch.object(workaround,'run',return_value=self.job), patch.object(workaround,'install') as install:
            workaround.ensure()
            install.assert_called_once()

    def test_resource_only_update_refreshes_copy(self):
        (workaround.SOURCE/'Contents/_CodeSignature/CodeResources').write_bytes(b'sealed resources v2')
        with patch.object(workaround,'run',return_value=self.job), patch.object(workaround,'install') as install:
            workaround.ensure()
            install.assert_called_once()

    def test_unexpected_launch_path_is_not_overwritten(self):
        self.agent['Program']='/Applications/Unrelated.app/Contents/MacOS/Unrelated'
        original=plistlib.dumps(self.agent)
        workaround.AGENT.write_bytes(original)
        with patch.object(workaround,'run') as run, patch.object(workaround,'install') as install:
            with self.assertRaisesRegex(RuntimeError,'Unexpected helper path'):
                workaround.ensure()
            install.assert_not_called()
            run.assert_not_called()
        self.assertEqual(workaround.AGENT.read_bytes(),original)

    def test_restore_preserves_current_unrelated_fields(self):
        original=dict(self.agent,Program=str(workaround.SOURCE/workaround.EXECUTABLE),RunAtLoad=False)
        workaround.BACKUP.write_bytes(plistlib.dumps(original))
        with patch.object(workaround,'reload_agent') as reload, patch.object(workaround,'run',return_value=self.job):
            workaround.restore()
            reload.assert_called_once()
        restored=plistlib.loads(workaround.AGENT.read_bytes())
        self.assertEqual(restored,dict(self.agent,Program=original['Program']))

    def test_missing_installation_does_not_change_anything(self):
        with patch.object(workaround,'SOURCE',Path(self.temp.name)/'absent'), patch.object(workaround,'install') as install:
            workaround.ensure()
            install.assert_not_called()

    def test_migration_preserves_rollback_and_does_not_overwrite_current_state(self):
        legacy=Path(self.temp.name)/'legacy'
        legacy.mkdir()
        (legacy/workaround.BACKUP.name).write_bytes(b'original backup')
        (legacy/workaround.MARKER.name).write_bytes(b'legacy marker')
        workaround.MARKER.write_bytes(b'current marker')
        with patch.object(workaround,'LEGACY_STATE',legacy):
            workaround.migrate_legacy_state()
            workaround.migrate_legacy_state()
        self.assertEqual(workaround.BACKUP.read_bytes(),b'original backup')
        self.assertEqual(workaround.MARKER.read_bytes(),b'current marker')

if __name__=='__main__':
    unittest.main()
