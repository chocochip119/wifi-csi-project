"""Minimal loopback authorization tests; run from repo root with python -m unittest scripts.test_wisensing_launcher."""
import http.client
import threading
import unittest
from http.server import ThreadingHTTPServer
from unittest.mock import patch

from scripts import wisensing_launcher as launcher


class LauncherHttpTests(unittest.TestCase):
    def test_stop_requires_correct_origin_and_token(self):
        token = "unit-test-long-unpredictable-token"
        server = ThreadingHTTPServer(("127.0.0.1", 0), launcher.make_handler(token))
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with patch.object(launcher, "CONTROL_PORT", port):
                def attempt(origin, given_token):
                    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
                    connection.request("POST", "/stop", headers={
                        "Host": f"127.0.0.1:{port}",
                        "Origin": origin,
                        "X-WiSensing-Token": given_token
                    })
                    response = connection.getresponse()
                    result = response.status
                    response.read()
                    connection.close()
                    return result

                self.assertEqual(attempt("http://untrusted.example", token), 403)
                self.assertEqual(attempt("http://127.0.0.1:5173", "wrong"), 403)
                self.assertTrue(thread.is_alive())
                self.assertEqual(attempt("http://127.0.0.1:5173", token), 200)
                thread.join(timeout=3)
                self.assertFalse(thread.is_alive())
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
