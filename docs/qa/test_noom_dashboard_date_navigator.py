#!/usr/bin/env python3
"""Contracts for the modern, compact Today date navigator."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DASHBOARD = (ROOT / "NoomApp/NoomApp/DashboardView.swift").read_text()


class NoomDashboardDateNavigatorTests(unittest.TestCase):
    def test_today_uses_an_oura_inspired_day_navigator_not_toolbar_date_picker(self) -> None:
        for snippet in (
            "NoomDayNavigator(selection: $ctx.selectedDate)",
            "struct NoomDayNavigator",
            "private func previousDay()",
            "private func nextDay()",
            'Image(systemName: "chevron.left")',
            'Image(systemName: "chevron.right")',
            "Calendar.current.isDateInToday(selection)",
            "DragGesture(minimumDistance: 24)",
        ):
            self.assertIn(snippet, DASHBOARD)
        self.assertNotIn('DatePicker("Date", selection: $ctx.selectedDate', DASHBOARD)

    def test_tapping_the_compact_date_opens_a_graphical_calendar_sheet(self) -> None:
        for snippet in (
            ".sheet(isPresented: $showsCalendar)",
            'DatePicker("Choose date", selection: $selection',
            "displayedComponents: .date",
            ".datePickerStyle(.graphical)",
            '.accessibilityLabel("Choose date")',
        ):
            self.assertIn(snippet, DASHBOARD)

    def test_mobbin_oura_reference_is_recorded_in_source(self) -> None:
        self.assertIn("mobbin.com/explore/screens/c659bd1e-9301-4281-a238-422ceaff9e71", DASHBOARD)


if __name__ == "__main__":
    unittest.main()
