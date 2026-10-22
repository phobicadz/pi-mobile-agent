#!/usr/bin/env python3
"""
Classic FizzBuzz.

For numbers 1 to n:
    - print "Fizz" if divisible by 3
    - print "Buzz" if divisible by 5
    - print "FizzBuzz" if divisible by both
    - otherwise print the number itself

Usage:
    python fizzbuzz.py [n]
"""

import sys


def fizzbuzz(n: int) -> None:
    for i in range(1, n + 1):
        if i % 15 == 0:
            print("FizzBuzz")
        elif i % 3 == 0:
            print("Fizz")
        elif i % 5 == 0:
            print("Buzz")
        else:
            print(i)


if __name__ == "__main__":
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    fizzbuzz(limit)
