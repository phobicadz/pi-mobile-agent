#!/usr/bin/env python3
"""
Simple command-line To-Do list app.

Tasks are stored in a local JSON file (todo.json) so they persist
between runs.

Usage:
    python todo.py add "Buy milk"
    python todo.py list
    python todo.py done 2
    python todo.py remove 2
    python todo.py clear
"""

import json
import sys
from pathlib import Path

DATA_FILE = Path(__file__).parent / "todo.json"


def load_tasks() -> list[dict]:
    if not DATA_FILE.exists():
        return []
    with open(DATA_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def save_tasks(tasks: list[dict]) -> None:
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(tasks, f, indent=2)


def add_task(text: str) -> None:
    tasks = load_tasks()
    tasks.append({"text": text, "done": False})
    save_tasks(tasks)
    print(f"Added: \"{text}\"")


def list_tasks() -> None:
    tasks = load_tasks()
    if not tasks:
        print("No tasks yet. Add one with: python todo.py add \"Your task\"")
        return

    for i, task in enumerate(tasks, start=1):
        status = "x" if task["done"] else " "
        print(f"[{status}] {i}. {task['text']}")


def mark_done(index: int) -> None:
    tasks = load_tasks()
    if not (1 <= index <= len(tasks)):
        print(f"No task with number {index}.")
        return

    tasks[index - 1]["done"] = True
    save_tasks(tasks)
    print(f"Marked done: \"{tasks[index - 1]['text']}\"")


def remove_task(index: int) -> None:
    tasks = load_tasks()
    if not (1 <= index <= len(tasks)):
        print(f"No task with number {index}.")
        return

    removed = tasks.pop(index - 1)
    save_tasks(tasks)
    print(f"Removed: \"{removed['text']}\"")


def clear_tasks() -> None:
    save_tasks([])
    print("All tasks cleared.")


def print_usage() -> None:
    print(__doc__)


def main() -> None:
    if len(sys.argv) < 2:
        print_usage()
        return

    command = sys.argv[1]

    if command == "add" and len(sys.argv) > 2:
        add_task(" ".join(sys.argv[2:]))
    elif command == "list":
        list_tasks()
    elif command == "done" and len(sys.argv) > 2:
        mark_done(int(sys.argv[2]))
    elif command == "remove" and len(sys.argv) > 2:
        remove_task(int(sys.argv[2]))
    elif command == "clear":
        clear_tasks()
    else:
        print_usage()


if __name__ == "__main__":
    main()
