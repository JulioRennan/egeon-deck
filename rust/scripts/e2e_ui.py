#!/usr/bin/env python3
"""Cliente mínimo do canal /ui (NDJSON) para o e2e.sh: manda um comando e
imprime a resposta (a linha com o `re` dele) como JSON em uma linha.

    e2e_ui.py <socket> '<json do comando sem id>'

Sai com 0 se a resposta veio com ok true, 1 se veio com erro, 2 se o canal
falhou. O canal fica aberto só durante a chamada: o estado está no core.
"""
import json
import socket
import sys

LIMITE = 15


def main() -> int:
    sock_path, raw = sys.argv[1], sys.argv[2]
    command = json.loads(raw)
    command["id"] = 1
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(LIMITE)
    try:
        s.connect(sock_path)
        s.sendall(b"GET /ui HTTP/1.1\r\nUpgrade: egeon-ndjson\r\n\r\n")
        s.sendall(json.dumps(command).encode() + b"\n")
        buffer = b""
        head_done = False
        while True:
            chunk = s.recv(65536)
            if not chunk:
                print("canal fechou sem resposta", file=sys.stderr)
                return 2
            buffer += chunk
            if not head_done:
                if b"\r\n\r\n" not in buffer:
                    continue
                buffer = buffer.split(b"\r\n\r\n", 1)[1]
                head_done = True
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                if not line.strip():
                    continue
                message = json.loads(line)
                if message.get("re") == 1:
                    print(json.dumps(message, ensure_ascii=False))
                    return 0 if message.get("ok") else 1
    except (OSError, ValueError) as err:
        print(f"canal /ui: {err}", file=sys.stderr)
        return 2
    finally:
        s.close()


if __name__ == "__main__":
    sys.exit(main())
