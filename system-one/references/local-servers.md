# Local and alternative System One servers

Jev's weights are closed; TypeSafe serves it only from `https://api.typesafe.ai`.
Independent projects rebuild the typed-decision idea on open weights behind the
same `/v1/systemone` wire API, so the helper script, the official SDKs
(`TYPESAFE_BASE_URL`), and the question-design guidance work unchanged. They are
not Jev: calibration, accuracy, and limits are their own. Validate thresholds on
labeled data per model before wiring them into production, and log the response's
`model` field with every decision.

| Server | Default base URL | Runtime | Key | Notes |
| --- | --- | --- | --- | --- |
| ollajev | `http://127.0.0.1:8000` | llama.cpp (GGUF) or PyTorch; pulls models from Hugging Face | None unless `OLLAJEV_API_KEY` is set (required to bind beyond loopback) | Ollama-style CLI: `serve`, `pull`, `list`, `ps`, `run`. Playground at `/playground`. Default model `Mapika/decider-4b-GGUF:Q4_K_M`; `jev-latest` or a missing `model` selects the default. |
| OpenJev | `http://127.0.0.1:8080` | vLLM on NVIDIA GPU or MLX on Apple silicon; DiffusionGemma 26B-A4B | Server-configured | Also serves `/v1/chat/completions`. Accepts `jev-latest` and `jev-preview` so SDK defaults work. Text and image questions. |
| Codiv (hosted mirror of OpenJev) | `https://api.codiv.ai` | Hosted | `TYPESAFE_API_KEY=sk-codiv-...` | Free tier at the time of writing; not local. |
| TypeSafe Jev | `https://api.typesafe.ai` | Hosted, closed weights | `TYPESAFE_API_KEY` from console.typesafe.ai | The reference; versioned ids and calibrated confidence. |

In-process libraries such as Laya-MLX and `@receptron/laya` expose no HTTP
server; this skill's helper does not reach them. Wrap them yourself or use one of
the servers above.

## Reach a running server

```bash
curl -fsS --max-time 5 http://127.0.0.1:8000/v1/models
```

Success means the server is up and the response lists what it will accept in
`model`. The helper's `probe` command runs this check across the default ports.

## Start a server (only when the user asks)

ollajev installs with `uv tool install ollajev` (or the project's install
script); on Linux it compiles llama.cpp and expects a C/C++ toolchain. Then:

```bash
ollajev pull Mapika/decider-4b-GGUF:Q4_K_M
ollajev serve Mapika/decider-4b-GGUF:Q4_K_M --no-browser
```

The server binds `127.0.0.1:8000` by default (`OLLAJEV_HOST` changes it) and
loads models on first use. Run it detached when the shell must return, and
confirm readiness by polling `/v1/models` rather than sleeping. Leave server
lifecycle to the user: do not install, stop, or replace a server they did not
ask about.

OpenJev ships Docker and bare-metal recipes in its README (`:8080`). Hardware
guide: a 2B to 4B GGUF decider fits a 16 GB consumer GPU or CPU with room to
spare; OpenJev's 26B-A4B model wants a larger GPU.

## Environment variables the SDKs read

| Variable | Effect |
| --- | --- |
| `TYPESAFE_BASE_URL` | API root; set to a local server to redirect the stock SDK. |
| `TYPESAFE_API_KEY` | Bearer key. Required by the SDKs even for keyless servers (any non-empty placeholder works); the helper script omits the header when unset. |
| `TYPESAFE_DEFAULT_MODEL` | Default `model` for SDK calls. |
| `TYPESAFE_LOG_LEVEL` | SDK logging; request and response bodies are not redacted, so avoid `debug` with sensitive state. |

## Sources

- https://pypi.org/project/ollajev/
- https://github.com/razorback16/openjev
- https://docs.typesafe.ai/sdk/python/api/clients/sync.md
