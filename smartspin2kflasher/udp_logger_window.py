import ifaddr
import socket
from socket import timeout
import threading
import tkinter as tk
from tkinter import ttk

UDP_PORT = 10000

class UdpLoggerWindow(tk.Toplevel):
    def __init__(self, parent):
        super().__init__(parent)
        
        self.title("UDP Logger")
        self.geometry("725x650")
        self.minsize(640, 480)

        self._logging_thread = None
        self._running = True

        self._init_ui()
        
        # Center the window
        self.update_idletasks()
        width = self.winfo_width()
        height = self.winfo_height()
        x = (self.winfo_screenwidth() // 2) - (width // 2)
        y = (self.winfo_screenheight() // 2) - (height // 2)
        self.geometry('{}x{}+{}+{}'.format(width, height, x, y))

        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _init_ui(self):
        main_frame = ttk.Frame(self, padding="15")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # Network interface selection
        interface_frame = ttk.Frame(main_frame)
        interface_frame.grid(row=0, column=0, sticky=(tk.W, tk.E), pady=(0, 5))
        interface_frame.grid_columnconfigure(1, weight=1)

        ttk.Label(interface_frame, text="Network Interface: ").grid(row=0, column=0, sticky=tk.W)
        
        self.ip_var = tk.StringVar()
        self.ip_choice = ttk.Combobox(interface_frame, textvariable=self.ip_var)
        self.ip_choice.grid(row=0, column=1, sticky=(tk.W, tk.E))
        
        # Populate network interfaces
        self.ip_addresses = list(self.get_network_interfaces())
        choices = []
        self.ip_data = {}  # Store IP data for each interface
        for ip in self.ip_addresses:
            nice_name = ip.nice_name
            choices.append(nice_name)
            self.ip_data[nice_name] = ip.ip
            
        self.ip_choice['values'] = choices
        if choices:
            self.ip_choice.set(choices[0])
        
        self.ip_choice.bind('<<ComboboxSelected>>', self._on_select_ip)

        # Console
        self.console_ctrl = tk.Text(main_frame, height=20, width=80, font=('TkFixedFont', 10))
        self.console_ctrl.grid(row=1, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        self.console_ctrl.configure(state='disabled', fg='white', bg='black')
        
        # Add scrollbar
        scrollbar = ttk.Scrollbar(main_frame, orient='vertical', command=self.console_ctrl.yview)
        scrollbar.grid(row=1, column=1, sticky=(tk.N, tk.S))
        self.console_ctrl['yscrollcommand'] = scrollbar.set

        # Configure grid weights
        main_frame.grid_columnconfigure(0, weight=1)
        main_frame.grid_rowconfigure(1, weight=1)

    def log_message(self, message):
        try:
            self.console_ctrl.configure(state='normal')
            if isinstance(message, bytes):
                message = message.decode('utf-8', errors='replace')
            self.console_ctrl.insert(tk.END, message)
            self.console_ctrl.configure(state='disabled')
            self.console_ctrl.see(tk.END)
        except:  # console_ctrl could be disposed but Thread is running
            pass

    def get_network_interfaces(self):
        network_ports = ifaddr.get_adapters()
        ip_addresses = []
        for port in network_ports:
            for ip in port.ips:
                if ip.is_IPv4 and self.can_connect(ip):
                    ip_addresses.append(ip)
        return ip_addresses

    def can_connect(self, ip):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.bind((ip.ip, UDP_PORT))
            sock.close()
        except Exception as exc:
            return False
        return True

    def _on_select_ip(self, event):
        self.stop_thread()

        selected = self.ip_var.get()
        ip = self.ip_data.get(selected)
        if ip:
            self._running = True
            self._logging_thread = threading.Thread(
                target=self.collect_logs,
                args=(self.thread_running, selected, ip)
            )
            self._logging_thread.start()

    def collect_logs(self, running, network_name, ip):
        try:
            udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            udp_socket.settimeout(0.5)
            udp_socket.bind((ip, UDP_PORT))
            self.log_message(f'Listening to : {network_name} ({ip}:{UDP_PORT})\n')
            while running():
                try:
                    data = udp_socket.recv(1024)
                    self.log_message(data)
                except timeout:
                    pass

            udp_socket.close()

        except Exception as exc:
            self.log_message(f'Can not connect to : {network_name} ({ip}:{UDP_PORT}). Error = {exc}\n')
            return

    def thread_running(self):
        return self._running

    def stop_thread(self):
        if self._logging_thread is not None:
            self._running = False
            self._logging_thread.join()

    def _on_close(self):
        self.stop_thread()
        self.destroy()
