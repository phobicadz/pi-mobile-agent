"""
Simple Flask To-Do list app.

Tasks are stored in a local JSON file (todo.json) so they persist
between restarts.

Run:
    pip install -r requirements.txt
    python app.py

Then open http://127.0.0.1:5000 in your browser.
"""

import json
from pathlib import Path

from flask import Flask, redirect, render_template, request, url_for

app = Flask(__name__)

DATA_FILE = Path(__file__).parent / "todo.json"


def load_tasks() -> list[dict]:
    if not DATA_FILE.exists():
        return []
    with open(DATA_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def save_tasks(tasks: list[dict]) -> None:
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(tasks, f, indent=2)


@app.route("/")
def index():
    tasks = load_tasks()
    return render_template("index.html", tasks=tasks)


@app.route("/add", methods=["POST"])
def add():
    text = request.form.get("task", "").strip()
    if text:
        tasks = load_tasks()
        tasks.append({"text": text, "done": False})
        save_tasks(tasks)
    return redirect(url_for("index"))


@app.route("/toggle/<int:index>", methods=["POST"])
def toggle(index: int):
    tasks = load_tasks()
    if 0 <= index < len(tasks):
        tasks[index]["done"] = not tasks[index]["done"]
        save_tasks(tasks)
    return redirect(url_for("index"))


@app.route("/delete/<int:index>", methods=["POST"])
def delete(index: int):
    tasks = load_tasks()
    if 0 <= index < len(tasks):
        tasks.pop(index)
        save_tasks(tasks)
    return redirect(url_for("index"))


@app.route("/clear", methods=["POST"])
def clear():
    save_tasks([])
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(debug=True)
