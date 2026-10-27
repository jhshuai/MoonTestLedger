"""Project-authored producer input, Apache-2.0; deliberately failing cases."""
import pytest


@pytest.mark.parametrize("amount", [0, 100], ids=["empty", "full"])
def test_amount(amount):
    print("captured payment output: 中文 <receipt>")
    assert amount >= 0


def test_failure():
    assert 1 == 2, "payment rejected <declined>"


@pytest.fixture
def unavailable():
    raise RuntimeError("setup unavailable")


def test_setup_error(unavailable):
    pass


@pytest.mark.skip(reason="requires external service")
def test_offline():
    pass
