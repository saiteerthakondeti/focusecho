from itertools import product
import json

import pytest

from automation.reports.full_suite_excel_report import SuiteCaseEntry, validate_against_ci_gate

SUITES = ("Backend (Pytest)", "QA Catalogue Controls", "Flutter Tests (Mobile/Web)",
          "Browser Extension Tests", "Selenium Acceptance", "Load Smoke", "Vulnerability Checks")
OUTCOMES = ("Passed", "Failed", "Skipped")
PAIRS = list(product(OUTCOMES, repeat=2))
CHANGES = ("unchanged", "omit first", "duplicate first", "append failure", "append pass", "append skip")


@pytest.mark.parametrize("suite,original,change", product(SUITES, PAIRS, CHANGES))
def test_workbook_reconciliation(tmp_path, suite, original, change):
    expected = dict(total=2, passed=original.count("Passed"), failed=original.count("Failed"),
                    skipped=original.count("Skipped"))
    (tmp_path/"ci-gate.json").write_text(json.dumps({"suites": {suite: expected}}))
    observed = list(original)
    if change == "omit first":
        observed.pop(0)
    elif change == "duplicate first":
        observed.append(original[0])
    elif change.startswith("append"):
        observed.append({"append failure":"Failed","append pass":"Passed","append skip":"Skipped"}[change])
    rows = [SuiteCaseEntry(suite, str(i), "case", status) for i,status in enumerate(observed)]
    valid, errors = validate_against_ci_gate(rows,tmp_path)
    assert valid == (change == "unchanged")
    assert bool(errors) != valid


def test_gate_detects_pass_failure_status_swap(tmp_path):
    suite = SUITES[0]
    (tmp_path/"ci-gate.json").write_text(json.dumps({"suites":{suite:dict(total=1,passed=1,failed=0)}}))
    valid, errors = validate_against_ci_gate([SuiteCaseEntry(suite,"B1","health","Failed")],tmp_path)
    assert not valid and any("passed count mismatch" in msg for msg in errors)
