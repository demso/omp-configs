#!/usr/bin/env python3
import io
import json
import os
import struct
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import torch

HOST = "127.0.0.1"
PORT = 30179
SAMPLE_RATE = 48000
MODEL_URL = "https://models.silero.ai/models/tts/ru/v5_5_ru.pt"
MODEL_PATH = Path(__file__).with_name("v5_5_ru.pt")
SPEAKERS = {"aidar", "baya", "kseniya", "xenia", "eugene"}
MAX_TEXT_LENGTH = 5000


def load_model():
    if not MODEL_PATH.exists():
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    torch.set_num_threads(max(1, min(4, os.cpu_count() or 1)))
    model = torch.package.PackageImporter(str(MODEL_PATH)).load_pickle("tts_models", "model")
    model.to(torch.device("cpu"))
    return model


MODEL = load_model()


def wav_bytes(audio) -> bytes:
    samples = audio.detach().cpu().clamp(-1, 1).mul(32767).to(torch.int16).tolist()
    raw = struct.pack(f"<{len(samples)}h", *samples)
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(raw)
    return output.getvalue()


class Handler(BaseHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        if self.path != "/health":
            self.send_error(404)
            return
        body = json.dumps({"status": "ok", "speakers": sorted(SPEAKERS)}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/synthesize":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
            text = str(payload.get("text", "")).strip()
            speaker = str(payload.get("speaker", "xenia"))
            if not text or len(text) > MAX_TEXT_LENGTH:
                raise ValueError(f"text must contain 1-{MAX_TEXT_LENGTH} characters")
            if speaker not in SPEAKERS:
                raise ValueError("unknown speaker")
            audio = MODEL.apply_tts(text=text, speaker=speaker, sample_rate=SAMPLE_RATE)
            body = wav_bytes(audio)
        except (ValueError, TypeError, json.JSONDecodeError) as error:
            body = json.dumps({"error": str(error)}).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        print(f"[{self.log_date_time_string()}] {format % args}", flush=True)


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Silero TTS ready at http://{HOST}:{PORT}", flush=True)
    server.serve_forever()
