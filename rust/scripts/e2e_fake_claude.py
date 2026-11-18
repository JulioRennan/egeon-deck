#!/usr/bin/env python3
"""Um `claude` de mentira para o e2e dos agentes (dono: dispatch).

Faz o que o app precisa ver do Claude Code, sem modelo nenhum:

- lê o `--settings` e roda os ganchos como o CLI: `SessionStart` na subida,
  `UserPromptSubmit` a cada prompt e `Stop` no fim do turno, com o payload em
  JSON no stdin (`session_id`, `transcript_path`, `last_assistant_message`);
- recebe o prompt pelo terminal, colado entre os marcadores do bracketed paste;
- no PRIMEIRO prompt, roda o comando entre crases que o papel (o
  `--append-system-prompt`) manda rodar "exatamente" — é o `egeon send`;
- grava a resposta no transcript e fecha o turno com `[[ED:ok]]`.

Só biblioteca padrão: roda com o python3 do sistema.
"""

import json
import os
import re
import subprocess
import sys
import time
import uuid

PASTE_START = "\x1b[200~"
PASTE_END = "\x1b[201~"


def arg(name):
    args = sys.argv[1:]
    if name in args:
        at = args.index(name)
        if at + 1 < len(args):
            return args[at + 1]
    return None


def say(text):
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


def hooks(settings, event):
    entries = settings.get("hooks", {}).get(event, [])
    return [h.get("command") for e in entries for h in e.get("hooks", []) if h.get("command")]


def run_hook(settings, event, payload):
    for command in hooks(settings, event):
        done = subprocess.run(
            command, shell=True, input=json.dumps(payload).encode(),
            capture_output=True, timeout=30,
        )
        if done.returncode != 0:
            say(f"fake-claude: gancho {event} saiu com {done.returncode}: "
                f"{done.stderr.decode(errors='replace').strip()[:200]}")


def stamp():
    # Com milissegundos, como o CLI: em segundos inteiros a linha parece mais
    # velha que o `prompt` do turno, e o app relê achando que é do turno passado.
    now = time.time()
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(now)) + f".{int(now % 1 * 1000):03d}Z"


def main():
    settings_path = arg("--settings")
    role = arg("--append-system-prompt") or ""
    session = arg("--session-id") or arg("--resume") or str(uuid.uuid4())
    settings = {}
    if settings_path:
        try:
            with open(settings_path) as f:
                settings = json.load(f)
        except OSError:
            say(f"fake-claude: sem o arquivo de ganchos {settings_path}")
    else:
        say("fake-claude: sem --settings, nenhum gancho")
    folder = os.path.join(os.environ.get("HOME", "/tmp"), "fake-transcripts")
    os.makedirs(folder, exist_ok=True)
    transcript = os.path.join(folder, f"{session}.jsonl")
    base = {"session_id": session, "transcript_path": transcript}

    # O comando que o papel manda rodar: o primeiro trecho entre crases depois
    # de "rode exatamente". Vai para `bash -c` como está: só serve porque o
    # papel é escrito pelo próprio e2e_agents.sh — papel vindo de fora seria
    # execução arbitrária.
    match = re.search(r"rode exatamente `([^`]+)`", role)
    action = match.group(1) if match else None

    run_hook(settings, "SessionStart", {**base, "hook_event_name": "SessionStart", "source": "startup"})
    say("fake claude pronto")

    acted = False
    pending = ""
    pasting = False
    stdin = sys.stdin.buffer
    while True:
        line = stdin.readline()
        if not line:
            return
        # No modo canônico do tty cada \n da colagem fecha uma linha, e o
        # Enter chega na mesma linha do fim da colagem.
        text = line.decode(errors="replace")
        if PASTE_START in text:
            pasting = True
            text = text.replace(PASTE_START, "")
        if pasting and PASTE_END not in text:
            pending += text
            continue
        pasting = False
        prompt = (pending + text.replace(PASTE_END, "")).strip()
        pending = ""
        if not prompt:
            continue
        say(f"> {prompt.splitlines()[0][:120]}")
        run_hook(settings, "UserPromptSubmit",
                 {**base, "hook_event_name": "UserPromptSubmit", "prompt": prompt})
        reply = "nada a fazer."
        if action and not acted:
            acted = True
            done = subprocess.run(["bash", "-c", action], capture_output=True, timeout=60)
            out = (done.stdout + done.stderr).decode(errors="replace").strip()
            say(f"$ {action}\n{out}")
            reply = f"rodei: {action}"
        reply += "\n\n[[ED:ok]]"
        with open(transcript, "a") as f:
            # Compacto, como o CLI grava: o app filtra a linha pelo texto
            # `"type":"assistant"` antes de ler o JSON.
            line = {"type": "assistant", "timestamp": stamp(),
                    "message": {"content": [{"type": "text", "text": reply}]}}
            f.write(json.dumps(line, separators=(",", ":"), ensure_ascii=False) + "\n")
        say(reply)
        run_hook(settings, "Stop", {**base, "hook_event_name": "Stop",
                                    "last_assistant_message": reply, "background_tasks": []})


if __name__ == "__main__":
    main()
