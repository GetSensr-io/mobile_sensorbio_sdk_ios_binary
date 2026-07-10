#!/usr/bin/env python3
"""Regression guard for live auth routing from debug sign-in/sign-up routes."""
from pathlib import Path
import unittest


CONTENT_VIEW = Path(__file__).resolve().parents[2] / "NoomApp/NoomApp/ContentView.swift"


class NoomAuthRoutingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = CONTENT_VIEW.read_text(encoding="utf-8")

    def test_authenticated_auth_qa_route_reaches_main_tabs(self) -> None:
        live_session_branch = "if let session, isLiveAuthRoute(qaRoute)"
        qa_host_branch = "else if let qaRoute"

        self.assertIn(live_session_branch, self.source)
        self.assertIn(qa_host_branch, self.source)
        self.assertLess(self.source.index(live_session_branch), self.source.index(qa_host_branch))

        helper_start = self.source.index("private func isLiveAuthRoute")
        helper_end = self.source.index("#endif", helper_start)
        helper = self.source[helper_start:helper_end]
        for route in ('\"signin\"', '\"sign_in\"', '\"signup\"'):
            self.assertIn(route, helper)

    def test_qa_routing_is_debug_only(self) -> None:
        conditional_start = self.source.index("#if DEBUG\n            if")
        else_start = self.source.index("#else", conditional_start)
        conditional_end = self.source.index("#endif", else_start)
        debug_body = self.source[conditional_start:else_start]
        release_body = self.source[else_start:conditional_end]

        self.assertIn("NoomQAHost(route: qaRoute)", debug_body)
        self.assertNotIn("NoomQAHost", release_body)
        self.assertNotIn("qaRoute", release_body)


if __name__ == "__main__":
    unittest.main()
