from __future__ import annotations

import json
from pathlib import Path
import re
from urllib.parse import quote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "ragnacustoms_api.lua"


def derive(score_endpoint: str) -> str:
    match = re.fullmatch(r"(https?)://([^/?#]+)(/wanapi/score/[^/?#]+)/?", score_endpoint.strip())
    if not match:
        raise ValueError("invalid configured score endpoint")
    scheme, host, path = match.groups()
    if scheme == "http" and urlsplit(score_endpoint).hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise ValueError("cleartext is loopback-only")
    return f"{scheme}://{host}{path}/vote"


def endpoint_from_key(base_url: str, api_key: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9._~-]+", api_key):
        raise ValueError("invalid API key")
    return derive(f"{base_url.rstrip('/')}/{api_key}")


def redact(endpoint: str) -> str:
    return re.sub(r"(/wanapi/score/)[^/?#]+", r"\1[redacted]", endpoint)


def main() -> int:
    assert derive("https://api.ragnacustoms.com/wanapi/score/secret") == (
        "https://api.ragnacustoms.com/wanapi/score/secret/vote"
    )
    assert derive("http://127.0.0.1:18080/wanapi/score/local-key/") == (
        "http://127.0.0.1:18080/wanapi/score/local-key/vote"
    )
    assert endpoint_from_key("https://api.ragnacustoms.com/wanapi/score", "consumer-key") == (
        "https://api.ragnacustoms.com/wanapi/score/consumer-key/vote"
    )
    for invalid_key in ["", "key/with/slash", "key?query"]:
        try:
            endpoint_from_key("https://api.ragnacustoms.com/wanapi/score", invalid_key)
        except ValueError:
            pass
        else:
            raise AssertionError(f"accepted invalid API key: {invalid_key}")
    for invalid in [
        "http://api.ragnacustoms.com/wanapi/score/secret",
        "https://api.ragnacustoms.com/vote/secret",
        "https://api.ragnacustoms.com/wanapi/score/secret/extra",
        "file:///wanapi/score/secret",
    ]:
        try:
            derive(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(f"accepted invalid endpoint: {invalid}")

    assert redact("https://host/wanapi/score/secret/vote") == "https://host/wanapi/score/[redacted]/vote"
    body = json.dumps({"beatmap": "abc123", "direction": "down"}, separators=(",", ":"))
    assert body == '{"beatmap":"abc123","direction":"down"}'
    assert f"?beatmap={quote('abc123', safe='')}" == "?beatmap=abc123"

    # Model the library's generation guard: only the newest response is applied.
    current_generation = 2
    applied: list[int] = []
    for response_generation in [1, 2]:
        if response_generation == current_generation:
            applied.append(response_generation)
    assert applied == [2]

    source = LIB.read_text()
    for expected in [
        'VERSION = "0.3.0"',
        '"/vote"',
        "CustomApiURLs",
        "GetCustomApiURLs",
        "VaRestRequestJSON",
        "subsystem:ConstructVaRestRequest()",
        "GetRequestObject",
        "unwrapRemoteValue(request:GetRequestObject())",
        'DecodeJson(body or "{}", true)',
        "DecodeJson",
        "ProcessURL",
        "GetResponseCode",
        "voteGenerations",
        "vote.stale",
        "function Api.getVote",
        "function Api.setVote",
        "function Api.clearVote",
        "function Api.deriveVoteEndpoint",
        "function Api.redactEndpoint",
        "[redacted]",
        "voteApiKey",
        "useWanApi",
        "wanApiScoreEndpoint",
        "scoreEndpointFromApiKey",
        "resolveVoteScoreEndpoint",
    ]:
        assert expected in source, f"missing vote client behavior: {expected}"
    vote_section = source[source.index("local function performVoteRequest") :]
    assert "httpPost(" not in vote_section
    assert "SetRequestObject" not in source
    assert "voteEndpointTemplate" not in source
    assert "options.scoreEndpoint" not in source
    assert "wanApiScoreEndpoint requires useWanApi=true" in source
    print("vote endpoint contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
