"""Tests for the calculator module."""

from calculator import add, multiply, subtract


def test_add() -> None:
    """The add helper returns a sum."""
    assert add(2, 3) == 5


def test_subtract() -> None:
    """The subtract helper returns a difference."""
    assert subtract(7, 2) == 5


def test_multiply() -> None:
    """The multiply helper returns a product."""
    assert multiply(4, 5) == 20
