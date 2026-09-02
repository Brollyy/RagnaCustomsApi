from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "Mods" / "RagnaCustomsVote" / "Scripts" / "main.lua"


def main() -> int:
    source = UI.read_text()
    for expected in [
        "RagnaCustomsApi >= 0.2.0",
        "FlatInGameEndPanel_C_",
        "VRInGameEnd",
        'or "vr"',
        'construct("/Script/UMG.Button"',
        "button:IsPressed()",
        "Api.getVote",
        "Api.setVote",
        'state.custom ~= true',
        'state.phase = "loading"',
        'state.phase = "submitting"',
        'state.phase = "ready"',
        'state.phase = "error"',
        "RemoveFromParent",
        "RagnaCustomsVoteSetBeatmapHash",
    ]:
        assert expected in source, f"missing Results UI behavior: {expected}"
    assert "OnClicked:Add" not in source
    assert "io.popen" not in source
    print("vote UI contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
