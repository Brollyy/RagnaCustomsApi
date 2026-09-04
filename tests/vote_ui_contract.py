from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "Mods" / "RagnaCustomsVote" / "Scripts" / "main.lua"


def main() -> int:
    source = UI.read_text()
    for expected in [
        "RagnaCustomsApi >= 0.2.0",
        'className = "FlatInGameEndPanel_C"',
        "VRInGameEnd",
        'mode = "vr"',
        'construct("/Script/UMG.CanvasPanel"',
        "standalone Results vote panel",
        "BndEvt__FlatInGameButton_Button_64_K2Node_ComponentBoundEvent_0_OnButtonPressedEvent__DelegateSignature",
        "BndEvt__Button_0_K2Node_ComponentBoundEvent_0_OnButtonPressedEvent__DelegateSignature",
        "voteDirectionForClickedButton",
        "clickedPath == entry.objectPath",
        "installButtonHooks()",
        "state.buttonHooksInstalled",
        "Api.getVote",
        "Api.setVote",
        'state.custom ~= true',
        'state.phase = "loading"',
        'state.phase = "submitting"',
        'state.phase = "ready"',
        'state.phase = "error"',
        "RemoveFromParent",
        "RagnaCustomsVoteSetBeatmapHash",
        'local owners = { "SongsManager" }',
        'text:match("^(-?%d+)$")',
        "manager:GetSong()",
        '"FlatBeatManager_C"',
        "manager:GetBeatMap()",
        "song:IsCustom()",
        "beatMap:GetHash()",
        'installHook("/Script/Ragnarock.BeatMap:GetHash"',
        "numeric = numeric + 4294967296",
        "captureOnGameThread",
        "findPlayedSongManager",
        "local canvas = findCanvas",
        "Default__WidgetBlueprintLibrary",
        "FlatInGameButton.FlatInGameButton_C",
        "WBP_Button_Basic.WBP_Button_Basic_C",
        "state.createQueued",
        "createOnGameThread",
        "numeric <= 4294967295",
        'objectName:find("/Engine/Transient.", 1, true)',
        'managerName:find("/Engine/Transient.", 1, true)',
    ]:
        assert expected in source, f"missing Results UI behavior: {expected}"
    assert "OnClicked:Add" not in source
    assert "state.currentVote == direction and nil or direction" not in source
    assert "if state.currentVote == direction then\n        desired = nil" in source
    assert "/Script/UMG.Button:SlateHandleClicked" not in source
    assert "io.popen" not in source
    assert 'FindAllOf("UserWidget")' not in source
    assert 'FindAllOf("CanvasPanel")' not in source
    assert 'FindAllOf("Button")' not in source
    assert 'FindAllOf("TextBlock")' not in source
    assert "resolvePlayedSongState()" not in source
    assert "resolvePlayedSongState(manager)" in source
    assert "button:AddChild(text)" not in source
    assert "button:SetContent(text)" not in source
    assert 'construct("/Script/UMG.Button"' not in source
    assert "FindFirstOf(candidate.className)" in source
    assert "FlatItem_PlayerStats" not in source
    live_override = (ROOT / "tests" / "live" / "local_test_override.lua").read_text()
    assert "scoreEndpoint" in live_override
    assert "beatmap" not in live_override
    assert "isCustom" not in live_override
    print("vote UI contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
