"""Exercise the persistent browser against a local HTML fixture."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time


def run_smoke() -> None:
    """Verify snapshot, axe, navigation, and graceful browser shutdown.

    Returns:
        None; raises on a failed assertion or command.
    """
    driver = Path(os.environ['BROWSER_DRIVER']).resolve()
    with tempfile.TemporaryDirectory(prefix='browser smoke ') as directory:
        state = Path(directory) / 'state'
        base = ['node', str(driver)]
        with (Path(directory) / 'launch.log').open('w+') as log:
            launch = subprocess.Popen(base + ['launch', '--state-dir', str(state)], stdout=log, stderr=log, start_new_session=True)
            try:
                for _ in range(100):
                    if (state / 'READY').exists():
                        break
                    if launch.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    time.sleep(0.1)
                assert (state / 'READY').exists(), 'browser never became ready'

                def command(name: str, *args: str) -> str:
                    """Send a command to this test's owned browser.

                    Args:
                        name: Browser command.
                        args: Command flags and values.
                    Returns:
                        Standard output, or raises on command failure.
                    """
                    return subprocess.check_output(base + [name, '--state-dir', str(state), *args], text=True, timeout=40)

                fixture = Path(directory) / 'fixture.html'
                fixture.write_text('<html lang="en"><title>Smoke</title><main><h1>Browser fixture</h1><button>Continue</button><img src="missing.png"></main></html>')
                command('navigate', '--url', fixture.as_uri())
                assert 'Browser fixture' in command('snapshot')
                command('viewport', '--width', '320', '--height', '640')
                annotated = json.loads(command('annotate', '--path', str(Path(directory) / 'shot.png')))
                assert annotated['refs']
                command('navigate', '--url', fixture.as_uri())
                stale = subprocess.run(base + ['click', '--state-dir', str(state), '--ref', '1'], capture_output=True)
                assert stale.returncode != 0
                result = json.loads(command('axe'))
                assert any(item['id'] == 'image-alt' for item in result['violations'])
                command('close')
                assert launch.wait(timeout=10) == 0
                assert not (state / 'READY').exists()
            finally:
                if launch.poll() is None:
                    os.killpg(launch.pid, signal.SIGKILL)
                    launch.wait(timeout=10)
    print('Browser lifecycle, snapshot, and axe tests passed')


if __name__ == '__main__':
    run_smoke()
