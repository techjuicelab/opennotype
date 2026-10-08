import pathlib
import shutil
import subprocess
import tempfile
import unittest


class PromptTestPackagingPaths(unittest.TestCase):
    def assert_rejects_staging_link(self, relative_path):
        source = pathlib.Path(__file__).with_name("build-prompt-test.sh")
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            scripts = root / "project/scripts"
            scripts.mkdir(parents=True)
            wrapper = scripts / source.name
            shutil.copy2(source, wrapper)
            called = root / "builder-was-called"
            (scripts / "build-app.sh").write_text(f"#!/bin/bash\ntouch '{called}'\nexit 0\n")
            (scripts / "build-app.sh").chmod(0o700)
            victim = root / "existing-install"
            victim.mkdir()
            marker = victim / "keep"
            marker.write_text("existing app must stay intact")
            link = root / "project" / relative_path
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(victim, target_is_directory=True)
            result = subprocess.run(["bash", str(wrapper)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Refusing a symlink", result.stderr)
            self.assertFalse(called.exists())
            self.assertEqual(marker.read_text(), "existing app must stay intact")

    def test_rejects_shared_builder_staging_parent_link_before_build(self):
        self.assert_rejects_staging_link("build/.staging")

    def test_rejects_shared_builder_staged_app_link_before_build(self):
        self.assert_rejects_staging_link("build/.staging/OpenNoType.app")


if __name__ == "__main__":
    unittest.main()
