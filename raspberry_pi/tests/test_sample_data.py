"""The files in sample_data/ must stay in step with what the running backend really returns."""
import json
import pathlib

from conftest import status

SAMPLES = pathlib.Path(__file__).resolve().parent.parent / "sample_data"


def shape(value):
    """The key structure of a JSON value, two levels deep."""
    if isinstance(value, dict):
        return {k: (sorted(v) if isinstance(v, dict) else None) for k, v in value.items()}
    return None


def load(name):
    return json.loads((SAMPLES / name).read_text(encoding="utf-8"))


def test_sample_status_files_have_the_same_shape_as_the_live_api(client):
    live = shape(status(client))
    for name in ("status_example.json", "status_with_alarm_example.json"):
        assert shape(load(name)) == live, f"{name} is out of date: regenerate it from the running backend"


def test_the_alarm_example_really_contains_an_alarm():
    items = load("status_with_alarm_example.json")["alarms"]["items"]
    assert items and {"id", "priority", "label", "active", "acknowledged"} <= set(items[0])


def test_sample_config_has_the_sections_the_backend_saves(client, config_file):
    client.post("/climate/settings", json={"enabled": False})         # makes the backend write its settings file
    saved = json.loads(config_file.read_text())
    assert set(load("config.example.json")) == set(saved)
