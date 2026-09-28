#!/data/data/com.termux/files/usr/bin/python3
# Minimal DHCP client for a single interface (Android/Termux).
# Usage (as root):  python3 dhcp.py <iface>
# Does DISCOVER -> OFFER -> REQUEST -> ACK, then configures addr+route via 'ip'.
import socket, struct, random, subprocess, sys, time, fcntl, os

MAGIC = b'\x63\x82\x53\x63'
BCAST = ('255.255.255.255', 67)

def get_mac(iface):
    with open('/sys/class/net/%s/address' % iface) as f:
        return bytes(int(x, 16) for x in f.read().strip().split(':'))

def build_msg(xid, mac, mtype, req_ip=None, server_ip=None, hostname='aic'):
    pkt = struct.pack('!BBBBIHH', 1, 1, 6, 0, xid, 0, 0x8000)
    pkt += b'\x00' * 16           # ciaddr yiaddr siaddr giaddr
    pkt += mac + b'\x00' * 10     # chaddr(16)
    pkt += b'\x00' * 64 + b'\x00' * 128
    pkt += MAGIC
    pkt += bytes([53, 1, mtype])
    if req_ip:
        pkt += bytes([50, 4]) + socket.inet_aton(req_ip)
    if server_ip:
        pkt += bytes([54, 4]) + socket.inet_aton(server_ip)
    pkt += bytes([12, len(hostname)]) + hostname.encode()
    # param request list: mask, router, dns, broadcast
    pkt += bytes([55, 4, 1, 3, 6, 28])
    pkt += b'\xff'
    if len(pkt) < 300:
        pkt += b'\x00' * (300 - len(pkt))
    return pkt

def parse(pkt):
    if pkt[0] != 2 or pkt[236:240] != MAGIC:
        return None
    opts, i = {}, 240
    while i < len(pkt):
        c = pkt[i]
        if c == 255: break
        if c == 0: i += 1; continue
        l = pkt[i + 1]
        opts[c] = pkt[i + 2:i + 2 + l]
        i += 2 + l
    return opts

def main():
    iface = sys.argv[1] if len(sys.argv) > 1 else 'wlan1'
    mac = get_mac(iface)
    xid = random.randint(0, 0xffffffff)

    SO_BINDTODEVICE = 25
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.setsockopt(socket.SOL_SOCKET, SO_BINDTODEVICE, iface.encode() + b'\x00')
    s.bind(('0.0.0.0', 68))
    s.settimeout(4)

    def send_recv(pkt, want):
        for _ in range(4):
            s.sendto(pkt, BCAST)
            t0 = time.time()
            while time.time() - t0 < 4:
                try:
                    d, _ = s.recvfrom(2048)
                except socket.timeout:
                    break
                o = parse(d)
                if o and struct.unpack('!I', d[4:8])[0] == xid and o.get(53, b'\x00')[0] == want:
                    return d, o
        return None, None

    print('[*] DHCPDISCOVER on %s (%s)' % (iface, ':'.join('%02x' % b for b in mac)))
    off_pkt, off = send_recv(build_msg(xid, mac, 1), 2)
    if not off:
        print('[-] no DHCPOFFER'); sys.exit(1)
    yi = socket.inet_ntoa(off_pkt[16:20])
    srv = socket.inet_ntoa(off.get(54, b'\x00\x00\x00\x00'))
    print('[*] OFFER %s (server %s)' % (yi, srv))

    ack_pkt, ack = send_recv(build_msg(xid, mac, 3, req_ip=yi, server_ip=srv), 5)
    if not ack:
        print('[-] no DHCPACK'); sys.exit(1)
    ip = socket.inet_ntoa(ack_pkt[16:20])
    mask = off.get(1) or ack.get(1, b'\xff\xff\xff\x00')
    r = ack.get(3) or off.get(3)
    gw = socket.inet_ntoa(r[:4]) if r else None
    prefix = bin(int.from_bytes(mask, 'big')).count('1')
    print('[+] ACK ip=%s/%d mask=%s gw=%s' % (ip, prefix, socket.inet_ntoa(mask), gw))

    def run(*a):
        print('    $', ' '.join(a)); subprocess.run(a, check=False)
    run('ip', 'addr', 'flush', 'dev', iface)
    run('ip', 'addr', 'add', '%s/%d' % (ip, prefix), 'dev', iface)
    if gw:
        # onlink: 网关与本接口同链路；Android 策略路由下必须显式 onlink 才加得上
        run('ip', 'route', 'replace', 'default', 'via', gw, 'dev', iface, 'onlink')
        # Android 的 ip rule 会把无标记流量送到 wlan0/不可达(priority 31000/32000)。
        # 在它之前插一条 lookup main，让 root/Termux 等无标记流量走本接口。
        run('ip', 'rule', 'del', 'priority', '30000')
        run('ip', 'rule', 'add', 'priority', '30000', 'lookup', 'main')
    dns = ack.get(6) or off.get(6)
    servers = []
    if dns:
        servers = [socket.inet_ntoa(dns[i:i+4]) for i in range(0, len(dns), 4)]
        print('[+] DNS: %s' % ' '.join(servers))
        try:
            with open('/data/local/tmp/aic/resolv.conf', 'w') as f:
                f.write(''.join('nameserver %s\n' % d for d in servers))
        except Exception as e:
            print('    (dns write: %s)' % e)
    # 记下租约，供 wifi-use.sh 切换默认上行时复用
    try:
        with open('/data/local/tmp/aic/lease', 'w') as f:
            f.write('ip=%s\n' % ip)
            f.write('gw=%s\n' % (gw or ''))
            f.write('dns=%s\n' % ' '.join(servers))
    except Exception as e:
        print('    (lease write: %s)' % e)

if __name__ == '__main__':
    main()
