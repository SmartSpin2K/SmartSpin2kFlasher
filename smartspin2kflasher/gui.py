# This GUI is a fork of the brilliant https://github.com/marcelstoer/nodemcu-pyflasher
import re
import sys
import threading
import tkinter as tk
from tkinter import ttk
from tkinter import filedialog
import base64
from io import BytesIO
from PIL import Image, ImageTk

from smartspin2kflasher.helpers import list_serial_ports
from smartspin2kflasher.udp_logger_window import UdpLoggerWindow

COLOR_RE = re.compile(r'(?:\033)(?:\[(.*?)[@-~]|\].*?(?:\007|\033\\))')
COLORS = {
    'black': 'black',
    'red': 'red',
    'green': 'green',
    'yellow': 'yellow',
    'blue': 'blue',
    'magenta': 'magenta',
    'cyan': 'cyan',
    'white': 'white',
}
FORE_COLORS = {**COLORS, None: 'white'}
BACK_COLORS = {**COLORS, None: 'black'}

class RedirectText:
    def __init__(self, text_widget):
        self._out = text_widget
        self._line = ''
        self._bold = False
        self._italic = False
        self._underline = False
        self._foreground = None
        self._background = None
        self._secret = False

    def _add_content(self, value):
        tags = []
        if self._bold:
            tags.append('bold')
        if self._italic:
            tags.append('italic')
        if self._underline:
            tags.append('underline')
        
        self._out.configure(state='normal')
        self._out.insert('end', value, ' '.join(tags))
        self._out.configure(state='disabled')
        self._out.see('end')
        
        # Update colors
        self._out.tag_configure('bold', font=('TkFixedFont', 10, 'bold'))
        self._out.tag_configure('italic', font=('TkFixedFont', 10, 'italic'))
        self._out.tag_configure('underline', underline=True)
        self._out.configure(fg=FORE_COLORS[self._foreground], bg=BACK_COLORS[self._background])

    def _write_line(self):
        pos = 0
        while True:
            match = COLOR_RE.search(self._line, pos)
            if match is None:
                break

            j = match.start()
            self._add_content(self._line[pos:j])
            pos = match.end()

            for code in match.group(1).split(';'):
                code = int(code)
                if code == 0:
                    self._bold = False
                    self._italic = False
                    self._underline = False
                    self._foreground = None
                    self._background = None
                    self._secret = False
                elif code == 1:
                    self._bold = True
                elif code == 3:
                    self._italic = True
                elif code == 4:
                    self._underline = True
                elif code == 5:
                    self._secret = True
                elif code == 6:
                    self._secret = False
                elif code == 22:
                    self._bold = False
                elif code == 23:
                    self._italic = False
                elif code == 24:
                    self._underline = False
                elif code == 30:
                    self._foreground = 'black'
                elif code == 31:
                    self._foreground = 'red'
                elif code == 32:
                    self._foreground = 'green'
                elif code == 33:
                    self._foreground = 'yellow'
                elif code == 34:
                    self._foreground = 'blue'
                elif code == 35:
                    self._foreground = 'magenta'
                elif code == 36:
                    self._foreground = 'cyan'
                elif code == 37:
                    self._foreground = 'white'
                elif code == 39:
                    self._foreground = None
                elif code == 40:
                    self._background = 'black'
                elif code == 41:
                    self._background = 'red'
                elif code == 42:
                    self._background = 'green'
                elif code == 43:
                    self._background = 'yellow'
                elif code == 44:
                    self._background = 'blue'
                elif code == 45:
                    self._background = 'magenta'
                elif code == 46:
                    self._background = 'cyan'
                elif code == 47:
                    self._background = 'white'
                elif code == 49:
                    self._background = None

        self._add_content(self._line[pos:])

    def write(self, string):
        for s in string:
            if s == '\r':
                self._out.configure(state='normal')
                last_line = self._out.get("end-2c linestart", "end-1c")
                self._out.delete("end-2c linestart", "end-1c")
                self._out.configure(state='disabled')
                self._write_line()
                self._line = ''
                continue
            self._line += s
            if s == '\n':
                self._write_line()
                self._line = ''
                continue

    def flush(self):
        pass

    def isatty(self):
        pass

class FlashingThread(threading.Thread):
    def __init__(self, parent, firmware, port, show_logs=False):
        threading.Thread.__init__(self)
        self.daemon = True
        self._parent = parent
        self._firmware = firmware
        self._port = port
        self._show_logs = show_logs

    def run(self):
        try:
            from smartspin2kflasher.__main__ import run_smartspin2kflasher

            argv = ['smartspin2kflasher', '--port', self._port, self._firmware]
            if self._show_logs:
                argv.append('--show-logs')
            run_smartspin2kflasher(argv)
        except Exception as e:
            print("Unexpected error: {}".format(e))
            raise

class MainFrame(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("SmartSpin2kFlasher")
        self.geometry("725x650")
        self.minsize(640, 480)

        self._firmware = None
        self._port = None

        self._init_ui()
        
        sys.stdout = RedirectText(self.console_ctrl)
        
        # Center the window
        self.update_idletasks()
        width = self.winfo_width()
        height = self.winfo_height()
        x = (self.winfo_screenwidth() // 2) - (width // 2)
        y = (self.winfo_screenheight() // 2) - (height // 2)
        self.geometry('{}x{}+{}+{}'.format(width, height, x, y))

    def _init_ui(self):
        main_frame = ttk.Frame(self, padding="15")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # Serial Port
        ttk.Label(main_frame, text="Serial port").grid(row=0, column=0, sticky=tk.W, pady=5)
        
        port_frame = ttk.Frame(main_frame)
        port_frame.grid(row=0, column=1, sticky=(tk.W, tk.E), pady=5)
        port_frame.grid_columnconfigure(0, weight=1)
        
        self.port_var = tk.StringVar()
        self.choice = ttk.Combobox(port_frame, textvariable=self.port_var)
        self.choice['values'] = self._get_serial_ports()
        if self.choice['values']:
            self.choice.set(self.choice['values'][0])
            self._port = self.choice['values'][0]
        self.choice.grid(row=0, column=0, sticky=(tk.W, tk.E))
        
        reload_btn = ttk.Button(port_frame, text="↻", width=3, command=self._on_reload)
        reload_btn.grid(row=0, column=1, padx=(5, 0))
        
        # File Picker
        ttk.Label(main_frame, text="Firmware").grid(row=1, column=0, sticky=tk.W, pady=5)
        
        def on_browse():
            filename = filedialog.askopenfilename()
            if filename:
                self._firmware = filename
                file_path.set(filename)
                
        file_frame = ttk.Frame(main_frame)
        file_frame.grid(row=1, column=1, sticky=(tk.W, tk.E), pady=5)
        file_frame.grid_columnconfigure(0, weight=1)
        
        file_path = tk.StringVar()
        ttk.Entry(file_frame, textvariable=file_path).grid(row=0, column=0, sticky=(tk.W, tk.E))
        ttk.Button(file_frame, text="Browse", command=on_browse).grid(row=0, column=1, padx=(5, 0))

        # Flash Button
        ttk.Button(main_frame, text="Flash SmartSpin2k", command=self._on_flash).grid(row=2, column=1, sticky=(tk.W, tk.E), pady=5)

        # Log Buttons
        log_frame = ttk.Frame(main_frame)
        log_frame.grid(row=3, column=1, sticky=(tk.W, tk.E), pady=5)
        log_frame.grid_columnconfigure(0, weight=1)
        log_frame.grid_columnconfigure(1, weight=1)
        
        ttk.Button(log_frame, text="View Logs", command=self._on_logs).grid(row=0, column=0, sticky=(tk.W, tk.E), padx=(0, 5))
        ttk.Button(log_frame, text="View UDP Logs", command=self._on_logs_udp).grid(row=0, column=1, sticky=(tk.W, tk.E))

        # Console
        ttk.Label(main_frame, text="Console").grid(row=4, column=0, columnspan=2, sticky=tk.W, pady=(5, 0))
        
        self.console_ctrl = tk.Text(main_frame, height=20, width=80, font=('TkFixedFont', 10))
        self.console_ctrl.grid(row=5, column=0, columnspan=2, sticky=(tk.W, tk.E, tk.N, tk.S), pady=(5, 0))
        self.console_ctrl.configure(state='disabled', fg='white', bg='black')
        
        # Add scrollbar
        scrollbar = ttk.Scrollbar(main_frame, orient='vertical', command=self.console_ctrl.yview)
        scrollbar.grid(row=5, column=2, sticky=(tk.N, tk.S), pady=(5, 0))
        self.console_ctrl['yscrollcommand'] = scrollbar.set

        # Configure grid weights
        main_frame.grid_columnconfigure(1, weight=1)
        main_frame.grid_rowconfigure(5, weight=1)

        # Bind events
        self.choice.bind('<<ComboboxSelected>>', self._on_select_port)
        self.protocol("WM_DELETE_WINDOW", self._on_exit_app)

    def _on_reload(self):
        ports = self._get_serial_ports()
        self.choice['values'] = ports
        if ports:
            self.choice.set(ports[0])
            self._port = ports[0]

    def _on_flash(self):
        self.console_ctrl.configure(state='normal')
        self.console_ctrl.delete('1.0', tk.END)
        self.console_ctrl.configure(state='disabled')
        worker = FlashingThread(self, self._firmware, self._port)
        worker.start()

    def _on_logs(self):
        self.console_ctrl.configure(state='normal')
        self.console_ctrl.delete('1.0', tk.END)
        self.console_ctrl.configure(state='disabled')
        worker = FlashingThread(self, 'dummy', self._port, show_logs=True)
        worker.start()

    def _on_logs_udp(self):
        logger_window = UdpLoggerWindow(self)
        logger_window.grab_set()

    def _on_select_port(self, event):
        self._port = self.port_var.get()

    def _get_serial_ports(self):
        ports = []
        for port, desc in list_serial_ports():
            ports.append(port)
        if not self._port and ports:
            self._port = ports[0]
        if not ports:
            ports.append("")
        return ports

    def _on_exit_app(self):
        self.quit()

    def log_message(self, message):
        self.console_ctrl.configure(state='normal')
        self.console_ctrl.insert(tk.END, message)
        self.console_ctrl.configure(state='disabled')
        self.console_ctrl.see(tk.END)

def main():
    app = MainFrame()
    app.mainloop()
