import tkinter as tk
from tkinter import scrolledtext, messagebox, ttk, simpledialog
import subprocess
import threading
import os
import time
import shutil
import re
import urllib.request
from datetime import datetime
from queue import Queue, Empty
import requests
import requests

import json

# --- CONFIGURACIÓN ---
CREATE_NO_WINDOW = 0x08000000 # Ocultar ventanas negras en Windows
SERVER_DIR = os.getcwd()
CONFIG_FILE = os.path.join(SERVER_DIR, "config.json")

DEFAULT_CONFIG = {
    "server_name": "",
    "playit_exe_path": r"C:\Program Files\playit_gg\bin\playit.exe",
    "backup_interval_seconds": 1800
}

def load_config():
    if not os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(DEFAULT_CONFIG, f, indent=4)
        except: pass
        return DEFAULT_CONFIG.copy()
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            return {**DEFAULT_CONFIG, **json.load(f)}
    except:
        return DEFAULT_CONFIG.copy()

def save_config(config_data):
    try:
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(config_data, f, indent=4)
    except: pass

CONFIG = load_config()

def get_world_name(server_dir):
    world_name = "Bedrock level"
    prop_path = os.path.join(server_dir, "server.properties")
    lines = []
    has_props = os.path.exists(prop_path)
    if has_props:
        try:
            with open(prop_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                for line in lines:
                    if line.startswith("level-name="):
                        world_name = line.split("=", 1)[1].strip()
                        break
        except: pass
    
    # Auto-detect folder if properties fail or mismatch, but there is exactly 1 folder in worlds/
    expected_path = os.path.join(server_dir, "worlds", world_name)
    if not os.path.exists(expected_path):
        try:
            worlds_path = os.path.join(server_dir, "worlds")
            if os.path.exists(worlds_path):
                dirs = [d for d in os.listdir(worlds_path) if os.path.isdir(os.path.join(worlds_path, d))]
                if len(dirs) == 1:
                    new_world = dirs[0]
                    # Reescribir server.properties si hay un mundo que forzar
                    if new_world != world_name and has_props and lines:
                        new_lines = []
                        for line in lines:
                            if line.startswith("level-name="):
                                new_lines.append(f"level-name={new_world}\n")
                            else:
                                new_lines.append(line)
                        with open(prop_path, 'w', encoding='utf-8') as f:
                            f.writelines(new_lines)
                    world_name = new_world
        except: pass
    return world_name

SERVER_EXE = "bedrock_server.exe"
PLAYIT_EXE = CONFIG.get("playit_exe_path", "")
WORLD_NAME = get_world_name(SERVER_DIR)
RESP_DIR = os.path.join(SERVER_DIR, "resp")
VERSION_FILE = os.path.join(SERVER_DIR, "version_actual.txt")
BACKUP_INTERVAL = CONFIG.get("backup_interval_seconds", 1800)
# Colores Premium
BG_COLOR = "#0c0d12"
HOVER_COLORS = {
    "#06d6a0": "#05b586",
    "#ef476f": "#d63d60",
    "#ffd166": "#e6bc5c",
    "#3a86ff": "#2a6cd9",
    "#222533": "#2a2e40"
}
CARD_COLOR = "#1a1c26"
TEXT_COLOR = "#e1e2e6"
ACCENT_BLUE = "#3a86ff"
ACCENT_GREEN = "#06d6a0"
ACCENT_RED = "#ef476f"
ACCENT_YELLOW = "#ffd166"
PANEL_COLOR = "#222533"

class MinecraftDashboard:
    def __init__(self, root):
        self.root = root
        
        # --- FIRST RUN CHECK ---
        self.server_name = CONFIG.get("server_name", "")
        if not self.server_name:
            self.root.withdraw() # Ocultar ventana principal durante el prompt
            user_input = simpledialog.askstring("Bienvenido", "¡Hola! Parece que es tu primera vez.\n\n¿Qué nombre le quieres dar a tu servidor de Minecraft?", parent=self.root)
            if user_input:
                self.server_name = user_input.strip()
            else:
                self.server_name = "Servidor de Minecraft" # Default fallback
            
            CONFIG["server_name"] = self.server_name
            save_config(CONFIG)
            self.update_server_properties_name(self.server_name)
            self.root.deiconify() # Mostrar ventana principal de nuevo
        
        self.root.title(f"Gestor - {self.server_name}")
        self.root.geometry("1150x900")
        self.root.configure(bg=BG_COLOR)
        
        self.server_proc = None
        self.playit_proc = None
        self.backup_thread = None
        self.stop_requested = False
        self.log_queue = Queue()
        
        self.setup_ui()
        self.root.after(100, self.process_logs)
        self.check_status_loop()
        
        # Al iniciar, buscar actualizaciones (opcionalmente)
        threading.Thread(target=self.check_version_startup, daemon=True).start()

    def update_server_properties_name(self, new_name):
        prop_path = os.path.join(SERVER_DIR, "server.properties")
        if not os.path.exists(prop_path): return
        try:
            with open(prop_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            for i, line in enumerate(lines):
                if line.startswith("server-name="):
                    lines[i] = f"server-name={new_name}\n"
                    break
            with open(prop_path, 'w', encoding='utf-8') as f:
                f.writelines(lines)
        except: pass

    def setup_ui(self):
        # --- Cabecera ---
        header = tk.Frame(self.root, bg=BG_COLOR, padx=30, pady=25)
        header.pack(fill="x")
        
        title_frame = tk.Frame(header, bg=BG_COLOR)
        title_frame.pack(side="left")
        
        display_name = self.server_name.upper() if len(self.server_name) <= 25 else self.server_name.upper()[:22] + "..."
        tk.Label(title_frame, text=display_name, font=("Segoe UI Black", 28), bg=BG_COLOR, fg=TEXT_COLOR).pack(anchor="w")
        tk.Label(title_frame, text="Consola de Administración Centralizada", font=("Segoe UI Semibold", 10), bg=BG_COLOR, fg=ACCENT_BLUE).pack(anchor="w")
        
        status_container = tk.Frame(header, bg=BG_COLOR)
        status_container.pack(side="right")
        
        tk.Label(status_container, text="ESTADO:", font=("Segoe UI", 10, "bold"), bg=BG_COLOR, fg="#888").pack(side="left", padx=10)
        self.status_badge = tk.Label(status_container, text="APAGADO", font=("Segoe UI", 12, "bold"), 
                                    bg=ACCENT_RED, fg="white", padx=20, pady=8, width=12)
        self.status_badge.pack(side="left")
        
        # --- Cuerpo ---
        body = tk.Frame(self.root, bg=BG_COLOR, padx=20, pady=10)
        body.pack(fill="both", expand=True)
        
        # Panel Izquierdo: Consola
        console_panel = tk.Frame(body, bg=BG_COLOR)
        console_panel.pack(side="left", fill="both", expand=True)
        
        self.console = scrolledtext.ScrolledText(console_panel, bg=CARD_COLOR, fg=TEXT_COLOR, font=("Consolas", 10), 
                                                borderwidth=0, highlightthickness=1, highlightbackground="#333",
                                                padx=10, pady=10)
        self.console.pack(fill="both", expand=True)
        
        input_frame = tk.Frame(console_panel, bg=CARD_COLOR, pady=10, padx=10)
        input_frame.pack(fill="x", pady=(10, 0))
        
        tk.Label(input_frame, text=">_", font=("Consolas", 12, "bold"), bg=CARD_COLOR, fg=ACCENT_BLUE).pack(side="left", padx=(0, 5))
        
        self.cmd_entry = tk.Entry(input_frame, bg=PANEL_COLOR, fg="white", insertbackground="white", 
                                  font=("Consolas", 11), borderwidth=0, relief="flat")
        self.cmd_entry.pack(side="left", fill="x", expand=True, ipady=6, padx=5)
        self.cmd_entry.bind("<Return>", lambda e: self.send_command())
        
        btn_send = tk.Button(input_frame, text="ENVIAR", font=("Segoe UI", 9, "bold"), bg=ACCENT_BLUE, fg="white", borderwidth=0, cursor="hand2", command=self.send_command, activebackground=HOVER_COLORS.get(ACCENT_BLUE, ACCENT_BLUE))
        btn_send.pack(side="right", padx=(5,0), ipadx=10, ipady=4)
        
        # Panel Derecho: Controles
        self.sidebar = tk.Frame(body, bg=BG_COLOR, width=350, padx=20)
        self.sidebar.pack(side="right", fill="y")
        self.sidebar.pack_propagate(False)
        
        # CONTROLES PRINCIPALES
        self.add_section_title("CONTROLES PRINCIPALES")
        self.btn_start = self.create_button("⚡ INICIAR SERVIDOR", ACCENT_GREEN, self.start_server)
        self.btn_stop = self.create_button("🛑 APAGADO SEGURO (60s)", ACCENT_RED, self.confirm_shutdown, state="disabled")
        self.btn_kill = self.create_button("💀 APAGADO FORZOSO", PANEL_COLOR, self.stop_server, state="disabled")
        
        # ACCIONES DE ACTUALIZACIÓN
        self.add_section_title("SISTEMA Y ACTUALIZACIÓN")
        self.btn_update = self.create_button("🔄 BUSCAR ACTUALIZACIÓN", PANEL_COLOR, self.check_updates_manual)
        self.btn_backup_now = self.create_button("💾 RESPALDO MANUAL", ACCENT_YELLOW, lambda: self.send_command("backup"), fg="black")

        # COMANDOS DE JUEGO
        self.add_section_title("COMANDOS DE ADMINISTRACIÓN")
        
        self.show_cheats_var = tk.BooleanVar(value=False)
        cb_cheats = tk.Checkbutton(self.sidebar, text="Mostrar comandos avanzados (Trucos)", 
                                   variable=self.show_cheats_var, bg=BG_COLOR, fg="#aaa", 
                                   selectcolor=BG_COLOR, activebackground=BG_COLOR, 
                                   activeforeground="white", cursor="hand2", 
                                   command=self.toggle_advanced_commands)
        cb_cheats.pack(anchor="w", pady=(0, 5))

        self.basic_cmd_frame = tk.Frame(self.sidebar, bg=BG_COLOR)
        self.basic_cmd_frame.pack(fill="x")
        
        self.create_admin_cmd_btn(self.basic_cmd_frame, "👥 Ver Jugadores", "list")
        self.create_admin_cmd_btn(self.basic_cmd_frame, "👑 Dar OP", "op")
        self.create_admin_cmd_btn(self.basic_cmd_frame, "🚫 Quitar OP", "deop")
        self.create_admin_cmd_btn(self.basic_cmd_frame, "👟 Kick Jugador", "kick")
        self.create_admin_cmd_btn(self.basic_cmd_frame, "🔨 Banear (Kick)", "ban")

        self.adv_cmd_frame = tk.Frame(self.sidebar, bg=BG_COLOR)
        # No empaquetamos adv_cmd_frame inicialmente
        
        self.create_admin_cmd_btn(self.adv_cmd_frame, "🎁 Dar Item (Give)", "give")
        self.create_admin_cmd_btn(self.adv_cmd_frame, "📍 Teletransportar", "tp")
        self.create_admin_cmd_btn(self.adv_cmd_frame, "🎮 Cambiar Gamemode", "gamemode")
        self.create_admin_cmd_btn(self.adv_cmd_frame, "🌤️ Cambiar Clima", "weather")
        self.create_admin_cmd_btn(self.adv_cmd_frame, "⏰ Cambiar Hora", "time")

        # Info del Sistema
        info_frame = tk.Frame(self.sidebar, bg=PANEL_COLOR, pady=15, padx=15)
        info_frame.pack(side="bottom", fill="x", pady=(20, 0))
        self.info_label = tk.Label(info_frame, text="Software listo.", font=("Segoe UI Italic", 9), 
                                  bg=PANEL_COLOR, fg="#aaa", justify="left")
        self.info_label.pack(fill="x")

    def add_section_title(self, text):
        tk.Label(self.sidebar, text=text, font=("Segoe UI Bold", 9), bg=BG_COLOR, fg="#666").pack(anchor="w", pady=(15, 5))

    def create_button(self, text, color, command, state="normal", fg="white"):
        btn = tk.Button(self.sidebar, text=text, font=("Segoe UI", 10, "bold"), 
                        bg=color, fg=fg, borderwidth=0, pady=10, cursor="hand2",
                        command=command, state=state, activebackground=HOVER_COLORS.get(color, color), activeforeground=fg)
        
        def on_enter(e):
            if btn['state'] == 'normal': btn['background'] = HOVER_COLORS.get(color, color)
        def on_leave(e):
            if btn['state'] == 'normal': btn['background'] = color
            
        btn.bind("<Enter>", on_enter)
        btn.bind("<Leave>", on_leave)
        btn.pack(fill="x", pady=4, padx=5)
        return btn

    def toggle_advanced_commands(self):
        if self.show_cheats_var.get():
            self.adv_cmd_frame.pack(fill="x")
        else:
            self.adv_cmd_frame.pack_forget()

    def create_admin_cmd_btn(self, parent, text, cmd_type):
        btn = tk.Button(parent, text=text, font=("Segoe UI", 9), 
                        bg=PANEL_COLOR, fg=TEXT_COLOR, borderwidth=0, pady=7, cursor="hand2",
                        command=lambda: self.handle_admin_cmd(cmd_type), activebackground=HOVER_COLORS.get(PANEL_COLOR, PANEL_COLOR), activeforeground="white")
        btn.bind("<Enter>", lambda e: e.widget.config(bg=HOVER_COLORS.get(PANEL_COLOR, PANEL_COLOR)))
        btn.bind("<Leave>", lambda e: e.widget.config(bg=PANEL_COLOR))
        btn.pack(fill="x", pady=3, padx=5)

    def handle_admin_cmd(self, cmd_type):
        if not self.server_proc:
            messagebox.showwarning("Aviso", "El servidor debe estar encendido para usar comandos.")
            return

        if cmd_type == "list": self.send_command("list")
        elif cmd_type == "op":
            user = simpledialog.askstring("Dar OP", "Nombre del jugador:")
            if user: self.send_command(f'op "{user}"')
        elif cmd_type == "deop":
            user = simpledialog.askstring("Quitar OP", "Nombre del jugador:")
            if user: self.send_command(f'deop "{user}"')
        elif cmd_type == "kick":
            user = simpledialog.askstring("Kick", "Nombre del jugador:")
            reason = simpledialog.askstring("Razón", "Razón (opcional):")
            if user: self.send_command(f'kick "{user}" {reason if reason else ""}')
        elif cmd_type == "ban":
            user = simpledialog.askstring("Banear", "Nombre del jugador:")
            if user: self.send_command(f'kick "{user}" BANEADO')
        elif cmd_type == "give":
            user = simpledialog.askstring("Give", "Jugador (@a para todos):")
            item = simpledialog.askstring("Item", "ID del item (ej. diamond):")
            cant = simpledialog.askstring("Cantidad", "Cantidad:", initialvalue="1")
            if user and item: self.send_command(f'give "{user}" {item} {cant}')
        elif cmd_type == "tp":
            origin = simpledialog.askstring("TP", "Jugador a teletransportar:")
            dest = simpledialog.askstring("TP", "Destino (Jugador o X Y Z):")
            if origin and dest: self.send_command(f'tp "{origin}" {dest}')
        elif cmd_type == "gamemode":
            user = simpledialog.askstring("Gamemode", "Jugador (@a para todos):")
            mode = simpledialog.askstring("Modo", "Modo (0:Survival, 1:Creative, 2:Adventure, 3:Spectator):")
            if user and mode: self.send_command(f'gamemode {mode} "{user}"')
        elif cmd_type == "weather":
            mode = simpledialog.askstring("Clima", "Tipo (clear, rain, thunder):")
            if mode: self.send_command(f'weather {mode}')
        elif cmd_type == "time":
            ticks = simpledialog.askstring("Hora", "Valor (0:Amanecer, 6000:Mediodía, 13000:Noche):")
            if ticks: self.send_command(f'time set {ticks}')

    def log(self, text, color=TEXT_COLOR):
        self.log_queue.put((text, color))

    def process_logs(self):
        try:
            while True:
                text, color = self.log_queue.get_nowait()
                self.console.insert(tk.END, text + "\n")
                self.console.see(tk.END)
        except Empty: pass
        self.root.after(100, self.process_logs)

    def start_server(self):
        if self.server_proc: return
        self.log(">>> [SISTEMA] Iniciando servidor...", ACCENT_BLUE)
        
        # Actualizar dinamicamente el nombre del mundo por si el usuario acaba de pegarlo
        global WORLD_NAME
        WORLD_NAME = get_world_name(SERVER_DIR)
        
        self.check_integrity()
        
        try:
            self.server_proc = subprocess.Popen([SERVER_EXE], cwd=SERVER_DIR, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
            threading.Thread(target=self.read_child_stdout, args=(self.server_proc,), daemon=True).start()
            
            if os.path.exists(PLAYIT_EXE):
                self.playit_proc = subprocess.Popen([PLAYIT_EXE], creationflags=subprocess.CREATE_NO_WINDOW)
                self.log(">>> [SISTEMA] Playit.gg iniciado.", ACCENT_GREEN)
            
            self.stop_requested = False
            self.backup_thread = threading.Thread(target=self.backup_loop, daemon=True)
            self.backup_thread.start()
            self.update_ui_state(True)
            
            # Actualizar la interfaz con el nombre correcto del mundo
            v_local = "Desconocida"
            if os.path.exists(VERSION_FILE):
                with open(VERSION_FILE, 'r') as f: v_local = f.read().strip()
            self.update_info_text(f"Mundo: {WORLD_NAME}\nVersión: {v_local}\nStatus: EN LÍNEA ✓")
                                  
        except Exception as e: messagebox.showerror("Error", f"Fallo al iniciar: {e}")

    def update_ui_state(self, running):
        self.btn_start.config(state="disabled" if running else "normal")
        self.btn_stop.config(state="normal" if running else "disabled")
        self.btn_kill.config(state="normal" if running else "disabled")
        self.status_badge.config(text="EN LÍNEA" if running else "APAGADO", bg=ACCENT_GREEN if running else ACCENT_RED)

    def stop_server(self, forced=True):
        if not self.server_proc: return
        self.log(">>> [SISTEMA] Apagando...", ACCENT_RED)
        self.stop_requested = True
        if not forced: self.send_command("stop")
        else: self.server_proc.kill()
        
        if self.playit_proc: self.playit_proc.terminate()
        self.server_proc = None
        self.playit_proc = None
        self.update_ui_state(False)

    def confirm_shutdown(self):
        if messagebox.askyesno("Apagado Seguro", "¿Deseas avisar a los jugadores y apagar en 60 segundos?"):
            threading.Thread(target=self.safe_shutdown_countdown, daemon=True).start()

    def safe_shutdown_countdown(self):
        times = [60, 30, 10, 5, 4, 3, 2, 1]
        for t in times:
            if not self.server_proc: return
            color = "§c" if t <= 10 else "§e"
            self.send_command(f'say {color} >> EL SERVIDOR SE CERRARÁ EN {t} SEGUNDOS...')
            time.sleep(30 if t == 60 else (20 if t == 30 else (5 if t == 10 else 1)))
        
        self.send_command("say §l§4 >> SERVIDOR APAGADO. ¡Hasta luego!")
        time.sleep(1)
        self.send_command("stop")

    def send_command(self, cmd=None):
        if not cmd:
            cmd = self.cmd_entry.get().strip(); self.cmd_entry.delete(0, tk.END)
        if not cmd: return
        if cmd == "backup": threading.Thread(target=self.do_backup, daemon=True).start(); return
        
        if self.server_proc and self.server_proc.poll() is None:
            self.server_proc.stdin.write(cmd + "\n"); self.server_proc.stdin.flush()
            self.log(f"  [COMANDO] > {cmd}", "#777")

    def read_child_stdout(self, proc):
        while True:
            line = proc.stdout.readline()
            if not line: break
            self.log(line.strip())

    def check_integrity(self):
        world_path = os.path.join(SERVER_DIR, "worlds", WORLD_NAME)
        if not os.path.exists(world_path): return
        if not os.path.exists(RESP_DIR): return
        backups = sorted([d for d in os.listdir(RESP_DIR) if d.startswith("resp-")], reverse=True)
        if not backups: return
        
        reciente = backups[0]
        backup_world = os.path.join(RESP_DIR, reciente, "worlds", WORLD_NAME)
        
        # Si en el backup más reciente no existe este mundo (ej. acaban de pegarlo), omitir
        if not os.path.exists(backup_world): return
        
        size_actual = self.get_dir_size(world_path)
        size_backup = self.get_dir_size(backup_world)
        
        if size_actual < size_backup:
            self.log(f"!!! [ALERTA] Mundo corrupto detectado ({size_actual} < {size_backup} bytes)", ACCENT_RED)
            shutil.rmtree(world_path)
            shutil.copytree(backup_world, world_path)
            self.log(">>> [ÉXITO] Restauración completa.", ACCENT_GREEN)

    def do_backup(self, is_update=False):
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M")
        prefijo = "resp-actualizacion" if is_update else "resp"
        dest = os.path.join(RESP_DIR, f"{prefijo}-{timestamp}")
        
        self.log(f">>> [RESPALDO] Iniciando respaldo de seguridad...", ACCENT_BLUE)
        if not is_update:
            self.send_command("say §l§e >> Iniciando Respaldo del Mundo...")
        
        try:
            os.makedirs(os.path.join(dest, "worlds"), exist_ok=True)
            
            prop_path = os.path.join(SERVER_DIR, "server.properties")
            if os.path.exists(prop_path):
                shutil.copy(prop_path, dest)
                
            src_world = os.path.join(SERVER_DIR, "worlds", WORLD_NAME)
            if os.path.exists(src_world):
                shutil.copytree(src_world, os.path.join(dest, "worlds"), dirs_exist_ok=True)
            
            self.log(">>> [ÉXITO] Respaldo guardado correctamente.", ACCENT_GREEN)
            if not is_update:
                self.send_command("say §l§a >> Respaldo Finalizado Correctamente. OK!")
            
            # Limpieza (mantener 3)
            todos = sorted([d for d in os.listdir(RESP_DIR) if d.startswith("resp-")], reverse=True)
            if len(todos) > 3:
                for old in todos[3:]: shutil.rmtree(os.path.join(RESP_DIR, old), ignore_errors=True)
            
            return dest
        except Exception as e:
            self.log(f">>> [ERROR] Falló el respaldo: {e}", ACCENT_RED)
            return None

    def backup_loop(self):
        while not self.stop_requested:
            for _ in range(BACKUP_INTERVAL):
                if self.stop_requested: break
                time.sleep(1)
            if not self.stop_requested: self.do_backup()

    def get_dir_size(self, path):
        total = 0
        try:
            for dirpath, dirnames, filenames in os.walk(path):
                for f in filenames: total += os.path.getsize(os.path.join(dirpath, f))
        except: pass
        return total

    def check_version_startup(self):
        self.log(">>> [SISTEMA] Iniciando exploración de versiones (Marzo 2026)...", "#555")
        try:
            # 1. Obtener versión local (UTF-8-SIG para evitar el ï»¿)
            v_local = "0.0.0.0"
            if os.path.exists(VERSION_FILE):
                try:
                    with open(VERSION_FILE, 'r', encoding='utf-8-sig') as f: 
                        v_local = f.read().strip()
                except:
                    with open(VERSION_FILE, 'r') as f: v_local = f.read().strip()
            
            # Limpiar posibles caracteres extraños
            v_local = "".join(c for c in v_local if c.isdigit() or c == '.')
            self.log(f">>> [SISTEMA] Versión local detectada: {v_local}", "#aaa")
            
            # 2. Intentar obtener info de la nube (Puente PowerShell Probing)
            status, ver_web, dl_url = self.fetch_latest_version_info(v_local)
            
            if status == "ok":
                # Limpiar versión web
                ver_web = "".join(c for c in ver_web if c.isdigit() or c == '.')
                self.latest_version_info = {"version": ver_web, "url": dl_url}
                self.log(f">>> [SISTEMA] Versión oficial en la nube: {ver_web}", ACCENT_BLUE)
                
                if v_local != ver_web:
                    self.log(f"!!! [AVISO] ¡Nueva versión disponible! ({ver_web})", ACCENT_YELLOW)
                    self.show_update_ui(ver_web)
                else:
                    self.log(">>> [SISTEMA] Tienes la versión estable más reciente activa.", ACCENT_GREEN)
                    self.update_info_text(f"Mundo: {WORLD_NAME}\nVersión: {v_local}\nEstatus: Al día ✓")
            else:
                self.log(">>> [SISTEMA] No hay parches nuevos inmediatos en el CDN oficial.", ACCENT_GREEN)
                self.log(">>> [INFO] Tu versión es la más reciente o el servidor de descarga está ocupado.", "#aaa")
                self.update_info_text(f"Mundo: {WORLD_NAME}\nVersión: {v_local}\nEstatus: Al día ✓")
        except Exception as e:
            self.log(f">>> [ERROR] En flujo de inicio: {e}", ACCENT_RED)


    def fetch_latest_version_info(self, v_local="0.0.0.0"):
        modern_ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36'
        
        # Helper: Limpiar y convertir versión a tupla para comparar
        def v_clean(v): return "".join(c for c in str(v) if c.isdigit() or c == '.')
        def v_to_tuple(v):
            try:
                clean = v_clean(v).strip('.')
                return tuple(map(int, (clean.split('.'))))
            except: return (0, 0, 0, 0)

        # --- ESTRATEGIA 1: API COMUNITARIA (ESTABLE Y SEGURA) ---
        self.log(">>> [SISTEMA] Consultando API de versiones (Comunidad)...", ACCENT_BLUE)
        api_url = "https://raw.githubusercontent.com/kittizz/bedrock-server-downloads/main/bedrock-server-downloads.json"
        try:
            resp = requests.get(api_url, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            
            # El JSON tiene estructura: {"release": {"1.26.3": {"windows": {"url": "..."}}}}
            if 'release' in data:
                releases = data['release']
                # Obtenemos la última clave del diccionario de lanzamientos
                last_ver_str = list(releases.keys())[-1]
                dl_url = releases[last_ver_str]['windows']['url']
                
                # Extraemos la versión real de 4 dígitos de la URL (más precisa que la clave)
                import re
                url_match = re.search(r'bedrock-server-(\d+\.\d+\.\d+\.\d+)\.zip', dl_url)
                ver_web = url_match.group(1) if url_match else last_ver_str
                
                if ver_web and dl_url:
                    if v_to_tuple(ver_web) >= v_to_tuple(v_local):
                        self.log(f">>> [ÉXITO] API detectó v{ver_web}", ACCENT_GREEN)
                        return "ok", ver_web, dl_url
        except Exception as e:
            self.log(f">>> [AVISO] Fallo en API: {e}. Intentando otros métodos...", "#777")

        # --- ESTRATEGIA 1: LECTURA DE NOTICIAS (NEWSTICKER) ---
        self.log(">>> [SISTEMA] Leyendo noticias oficiales (Changelogs)...", "#777")
        try:
            # Scrapeamos la sección de artículos buscando la versión más reciente mencionada
            ps_news_cmd = (
                f"$ProgressPreference = 'SilentlyContinue'; "
                f"$r = Invoke-WebRequest -Uri 'https://www.minecraft.net/en-us/articles' -UseBasicParsing -UserAgent '{modern_ua}'; "
                f"$r.Content"
            )
            proc_news = subprocess.run(["powershell", "-NoProfile", "-Command", ps_news_cmd], 
                                      capture_output=True, text=True, timeout=15, creationflags=CREATE_NO_WINDOW)
            
            if proc_news.returncode == 0 and proc_news.stdout:
                html = proc_news.stdout
                matches = re.findall(r'Bedrock Edition (\d+\.\d+(?:\.\d+)?(?:\.\d+)?)', html)
                if matches:
                    ver_news = matches[0]
                    parts = ver_news.split('.')
                    while len(parts) < 4: parts.append('0')
                    ver_final = ".".join(parts)
                    url_news = f"https://www.minecraft.net/bedrockdedicatedserver/bin-win/bedrock-server-{ver_final}.zip"
                    
                    check_cmd = f"$ProgressPreference = 'SilentlyContinue'; try {{ $r = Invoke-WebRequest -Uri '{url_news}' -Method Head -TimeoutSec 5; if ($r.StatusCode -eq 200) {{ 'OK' }} }} catch {{ }}"
                    proc_check = subprocess.run(["powershell", "-NoProfile", "-Command", check_cmd], 
                                              capture_output=True, text=True, creationflags=CREATE_NO_WINDOW)
                    if "OK" in proc_check.stdout:
                        self.log(f">>> [NOTICIA] Nueva versión detectada en Blog: v{ver_final}", ACCENT_GREEN)
                        return "ok", ver_final, url_news
        except Exception as e:
            self.log(f">>> [AVISO] No se pudo leer el blog de noticias: {e}", "#555")

        # --- ESTRATEGIA 2: SONDEO DIRECTO (FALLBACK FINAL) ---
        self.log(">>> [SISTEMA] Cambiando a modo sondeo (Probing)...", "#777")
        parts = v_local.split('.')
        if len(parts) < 4: parts += ['0'] * (4 - len(parts))
        v1, v2, v3, v4 = parts[0], parts[1], parts[2], parts[3]
        
        candidatos = []
        for i in range(1, 11): candidatos.append(f"{v1}.{v2}.{v3}.{int(v4)+i}")
        candidatos.append(f"{v1}.{int(v2)+1}.0.0")

        for ver in candidatos:
            url = f"https://www.minecraft.net/bedrockdedicatedserver/bin-win/bedrock-server-{ver}.zip"
            ps_cmd = f"$ProgressPreference = 'SilentlyContinue'; try {{ $r = Invoke-WebRequest -Uri '{url}' -Method Head -TimeoutSec 3 -UserAgent '{modern_ua}'; if ($r.StatusCode -eq 200) {{ 'OK' }} }} catch {{ }}"
            try:
                proc = subprocess.run(["powershell", "-NoProfile", "-Command", ps_cmd], 
                                     capture_output=True, text=True, timeout=5, creationflags=CREATE_NO_WINDOW)
                if "OK" in proc.stdout:
                    return "ok", ver, url
            except: pass
            time.sleep(0.05)

        return "error", None, None

    def show_update_ui(self, ver):
        self.update_info_text(f"¡ACTUALIZACIÓN DISPONIBLE!\nVersión: {ver}")
        self.info_label.config(fg=ACCENT_YELLOW, font=("Segoe UI Bold", 9))
        
        # Añadir botón de actualizar ahora en el sidebar
        if not hasattr(self, 'btn_do_update'):
            self.btn_do_update = self.create_button("✨ ACTUALIZAR AHORA", ACCENT_BLUE, self.start_update_flow)
            self.btn_do_update.pack(before=self.info_label.master, fill="x", pady=10)

    def update_info_text(self, text):
        self.info_label.config(text=text)

    def check_updates_manual(self):
        threading.Thread(target=self.run_update_process, daemon=True).start()

    def run_update_process(self):
        self.log(">>> [ACTUALIZACIÓN] Buscando...", ACCENT_BLUE)
        v_actual = "0.0.0.0"
        if os.path.exists(VERSION_FILE):
            with open(VERSION_FILE, 'r', encoding='utf-8-sig') as f: v_actual = f.read().strip()
        v_actual = "".join(c for c in v_actual if c.isdigit() or c == '.')
        
        status, ver_web, dl_url = self.fetch_latest_version_info(v_actual)
        
        if status == "ok":
            self.latest_version_info = {"version": ver_web, "url": dl_url}
            if v_actual == ver_web:
                messagebox.showinfo("La Maldición del Lag", f"Ya tienes la versión más reciente ({v_actual}).")
            else:
                self.show_update_ui(ver_web)
                messagebox.showinfo("Actualización", f"Versión {ver_web} disponible. Pulsa el botón azul 'ACTUALIZAR AHORA' para proceder.")
        else:
            messagebox.showinfo("La Maldición del Lag", "No se encontraron versiones nuevas en el servidor.")

    def start_update_flow(self):
        if self.server_proc:
            if messagebox.askyesno("Apagar Servidor", "El servidor debe estar apagado para actualizar.\n¿Deseas apagarlo ahora de forma segura?"):
                # Iniciar apagado y luego actualizar
                threading.Thread(target=self.shutdown_and_update, daemon=True).start()
            return
        
        threading.Thread(target=self.perform_full_update, daemon=True).start()

    def shutdown_and_update(self):
        self.safe_shutdown_countdown() # Avisar 60s
        while self.server_proc is not None:
            time.sleep(2)
        self.perform_full_update()

    def perform_full_update(self):
        ver = self.latest_version_info['version']
        url = self.latest_version_info['url']
        
        is_first_install = not os.path.exists(VERSION_FILE)
        
        self.log(f">>> [ACTUALIZACIÓN] Iniciando proceso para v{ver}...", ACCENT_BLUE)
        
        # 1. Respaldo previo
        backup_path = self.do_backup(is_update=True)
        if not backup_path:
            self.log(">>> [ERROR] No se pudo crear el respaldo de seguridad. Abortando actualización.", ACCENT_RED)
            return

        # 2. Descargar
        try:
            import tempfile, zipfile
            temp_zip = os.path.join(tempfile.gettempdir(), f"bedrock_v{ver}.zip")
            self.log(f">>> [ACTUALIZACIÓN] Descargando ZIP desde servidores oficiales...", "#aaa")
            
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req) as response, open(temp_zip, 'wb') as out_file:
                shutil.copyfileobj(response, out_file)
            
            # 3. Extraer
            self.log(">>> [ACTUALIZACIÓN] Extrayendo archivos...", "#aaa")
            extract_path = os.path.join(tempfile.gettempdir(), f"bedrock_extract_{ver}")
            if os.path.exists(extract_path): shutil.rmtree(extract_path)
            
            with zipfile.ZipFile(temp_zip, 'r') as zip_ref:
                zip_ref.extractall(extract_path)
            
            # 4. Instalar (Mover archivos)
            self.log(">>> [ACTUALIZACIÓN] Instalando nuevos binarios...", ACCENT_BLUE)
            for item in os.listdir(extract_path):
                s = os.path.join(extract_path, item)
                d = os.path.join(SERVER_DIR, item)
                
                # Omitir archivos que no deben tocarse
                if item in ["resp", "version_actual.txt"]: continue
                
                if os.path.isdir(s):
                    # Omitir mundos del ZIP, usaremos los nuestros
                    if item == "worlds": continue
                    shutil.copytree(s, d, dirs_exist_ok=True)
                else:
                    shutil.copy2(s, d)

            # 5. Restaurar configuración y mundo desde el respaldo
            self.log(">>> [ACTUALIZACIÓN] Restaurando configuración personalizada...", "#aaa")
            # Restaurar properties
            prop_backup = os.path.join(backup_path, "server.properties")
            if os.path.exists(prop_backup):
                shutil.copy2(prop_backup, SERVER_DIR)
            # Restaurar mundo
            src_world = os.path.join(backup_path, "worlds")
            dst_world = os.path.join(SERVER_DIR, "worlds", WORLD_NAME)
            if os.path.exists(src_world):
                shutil.copytree(src_world, dst_world, dirs_exist_ok=True)
            
            # 6. Finalizar
            with open(VERSION_FILE, 'w') as f: f.write(ver)
            self.log(f">>> [ÉXITO] Servidor actualizado a la versión {ver} correctamente.", ACCENT_GREEN)
            
            if is_first_install:
                messagebox.showinfo("Primera Instalación Completa", f"¡Binarios v{ver} descargados e instalados con éxito!\n\nPara garantizar que el servidor reconozca los nuevos archivos base, por favor **CIERRA** y vuelve a abrir el programa (reinicia el panel).", icon='warning')
            else:
                messagebox.showinfo("La Maldición del Lag", f"¡Actualización a v{ver} completada con éxito!")
            
            # Limpiar
            os.remove(temp_zip)
            shutil.rmtree(extract_path)
            if hasattr(self, 'btn_do_update'):
                self.btn_do_update.destroy()
                delattr(self, 'btn_do_update')
            self.update_ui_state(False)
            
        except Exception as e:
            self.log(f">>> [ERROR CRÍTICO] Durante la actualización: {e}", ACCENT_RED)
            messagebox.showerror("Error de Actualización", f"Ocurrió un error grave: {e}\nEl servidor podría necesitar reparación manual.")

    def check_status_loop(self):
        if self.server_proc and self.server_proc.poll() is not None:
            self.log(">>> [ALERTA] Servidor cerrado inesperadamente.", ACCENT_RED)
            self.server_proc = None; self.update_ui_state(False)
        self.root.after(2000, self.check_status_loop)

if __name__ == "__main__":
    root = tk.Tk(); ttk.Style().theme_use('clam'); app = MinecraftDashboard(root); root.mainloop()

