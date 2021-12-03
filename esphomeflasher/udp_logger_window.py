import wx
import socket
import ifaddr
import threading
import time

UDP_PORT = 10000


class UdpLoggerWindow(wx.Frame):
    def __init__(self, parent):
        wx.Frame.__init__(self, parent, -1, "UDP Logger", size=(725, 650),
                          style=wx.DEFAULT_FRAME_STYLE | wx.NO_FULL_REPAINT_ON_RESIZE)

        self.Bind(wx.EVT_CLOSE, self.on_close)
        self._logging_thread = None
        self._running = True

        wx.Frame.__init__(self, parent=parent, title='Udp Logger')
        self.SetMinSize((640, 480))

        panel = wx.Panel(self)

        # ip address selection
        ip_label = wx.StaticText(panel, label="Network Interface: ", style=wx.ALIGN_CENTRE)
        ip_choice = wx.Choice(panel, choices=[])
        ip_addresses = list(self.get_network_interfaces())
        for ip in ip_addresses:
            ip_choice.Append(ip.nice_name, ip.ip)
        ip_choice.Bind(wx.EVT_CHOICE, self.on_select_ip)

        ip_box = wx.BoxSizer(wx.HORIZONTAL)
        ip_box.Add(ip_label, 0, wx.ALIGN_LEFT, border=5)
        ip_box.AddStretchSpacer(0)
        ip_box.Add(ip_choice, 1, wx.EXPAND)

        # logger textCtrl
        self.console_ctrl = wx.TextCtrl(panel, style=wx.TE_MULTILINE | wx.TE_READONLY | wx.HSCROLL)
        self.console_ctrl.SetFont(wx.Font((0, 13), wx.FONTFAMILY_TELETYPE, wx.FONTSTYLE_NORMAL, wx.FONTWEIGHT_NORMAL))
        self.console_ctrl.SetBackgroundColour(wx.BLACK)
        self.console_ctrl.SetForegroundColour(wx.WHITE)
        self.console_ctrl.SetDefaultStyle(wx.TextAttr(wx.WHITE))

        logger_box = wx.BoxSizer(wx.VERTICAL)
        logger_box.Add(ip_box, 0, wx.BOTTOM, 3)
        logger_box.Add(self.console_ctrl, 1, wx.EXPAND)

        main_box = wx.BoxSizer(wx.VERTICAL)
        main_box.Add(logger_box, 1, wx.EXPAND | wx.ALL, 15)
        panel.SetSizerAndFit(main_box)

    def log_message(self, message):
        try:
            self.console_ctrl.AppendText(message)
        except: # console_ctrl could be disposed but Thread is running
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
            # print(exc)
            return False
        return True

    def on_select_ip(self, event):
        choice = event.GetEventObject()
        selection = choice.GetSelection()
        name = choice.GetString(selection)
        ip = choice.GetClientData(selection)

        self.stop_thread()

        self._running = True
        self._logging_thread = threading.Thread(target=self.collect_logs, args=(name, ip))
        self._logging_thread.start()

    def collect_logs(self, network_name, ip):
        try:
            udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            udp_socket.bind((ip, UDP_PORT))
            self.log_message(f'Listening to : {network_name} ({ip}:{UDP_PORT})\n')
            while self._running:
                data = udp_socket.recv(1024)
                self.log_message(data)
                time.sleep(1)

            udp_socket.close()

        except Exception as exc:
            self.log_message(f'Can not connect to : {network_name} ({ip}:{UDP_PORT}). Error = {exc}\n')
            return

    def stop_thread(self):
        if self._logging_thread is not None:
            self._running = False
            self._logging_thread.join()

    def on_close(self):
        self.stop_thread()
