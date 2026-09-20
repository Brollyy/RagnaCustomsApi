from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "ragnacustoms_api.lua"


def main() -> int:
    source = SOURCE.read_text()
    assert "local function responseBody(request)" in source
    assert "local returnedText = responseString(returned)" in source
    assert "return value:ToString()" in source
    assert source.count("request:GetResponseContentAsString(false)") == 1
    assert "request.ResponseContent:ToString()" not in source
    assert "local function apiRequest(method, path, body, callback)" in source
    assert source.count("return httpRequest(method, url, body, complete)") == 1
    assert "return apiRequest(\"POST\", path, \"\", function(response, err)" in source
    print("transport response-body contract: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
