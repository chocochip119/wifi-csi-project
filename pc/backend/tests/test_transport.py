from pathlib import Path
import queue
import socket
import struct
import subprocess
import threading
import time
import pytest
from protocol import wise_protocol as wp
from localization.ethernet_input import StreamDecoder, EthernetInput
from app.config import Settings
from app.service import BackendService

ROOT = Path(__file__).resolve().parents[3]


def until(check, timeout=4):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value: return value
        time.sleep(0.01)
    pytest.fail('condition timed out')


def free_port():
    sock = socket.socket()
    try:
        sock.bind(('127.0.0.1',0))
        return sock.getsockname()[1]
    finally:
        sock.close()


@pytest.fixture(scope='session')
def bridge_binary(tmp_path_factory):
    binary = tmp_path_factory.mktemp('cbridge')/'server'
    subprocess.run(['gcc','-std=c11','-Wall','-Wextra','-Werror','-pthread',
        '-I'+str(ROOT/'ps/include'),str(ROOT/'ps/tests/wise_test_server.c'),
        str(ROOT/'ps/src/wise_server.c'),str(ROOT/'ps/src/csi_pipeline.c'),
        str(ROOT/'ps/src/loc_ridge.c'),'-lm','-o',str(binary)],check=True)
    return binary


@pytest.fixture
def start_bridge(bridge_binary):
    """start_bridge(forward_csi, location) -> (port, send). One PS port carries every type."""
    procs = []

    def start(forward_csi=True, location=False):
        port = free_port()
        args = [str(bridge_binary),str(port),str(int(forward_csi))]
        if location:
            args.append(str(ROOT/'ps/models/loc_ridge_rx5.bin'))
        proc = subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,text=True,bufsize=1)
        procs.append(proc)
        replies = queue.Queue()
        def reader():
            for line in proc.stdout: replies.put(line.strip())
        threading.Thread(target=reader,daemon=True).start()
        assert replies.get(timeout=3) == 'READY'
        def send(command):
            proc.stdin.write(command+'\n'); proc.stdin.flush()
            return replies.get(timeout=3)
        return port, send

    yield start
    for proc in procs:
        proc.stdin.write('Q\n'); proc.stdin.flush()
        try:
            proc.wait(timeout=3)
            assert proc.returncode == 0, proc.stderr.read()
        finally:
            if proc.poll() is None: proc.kill(); proc.wait()


def usb(kind,payload,seq=45,corrupt=False):
    head = struct.pack('<IBBHI',0x35534943,1,kind,len(payload),seq)
    checksum = 0
    for byte in head+payload: checksum = (31*checksum+byte)&0xffffffff
    if corrupt: checksum ^= 1
    return head + struct.pack('<I',checksum) + payload


def status_payload():
    head = wp.STATUS_HEADER.pack(1,11,1,7,5,5,5,5,50000,1000,1,123,45,100,0,
                                bytes.fromhex('AABBCCDDEEFF'),b'\0\0')
    return head+b''.join(wp.STATUS_NODE.pack(i,i,i,7,bytes([2,0,0,0,0,i]),0,100,0) for i in range(5))


def cycle_payload(seq=123,missing=None,large=False):
    active = 8 if large else 5
    head = bytearray(32)
    struct.pack_into('<I',head,4,seq)
    head[28:31] = bytes([active,active-(missing is not None),int(missing is not None)])
    body = []
    for i in range(active):
        csi = b'' if i == missing else bytes([i,3])*(512 if large else 192)
        body.append(struct.pack('<BBbBH',i,int(bool(csi)),-40-i,0,len(csi))+csi)
    return bytes(head)+b''.join(body)


def read_packets(sock,count):
    decoder = StreamDecoder(); packets = []
    sock.settimeout(3)
    while len(packets) < count:
        data = sock.recv(65536)
        assert data, 'unexpected disconnect'
        packets.extend(decoder.feed(data))
    return packets


def test_c_usb_parser_tcp_framing_status_ack_csi_and_pose(start_bridge):
    port,send = start_bridge(forward_csi=True)
    # Cache validated STATUS even before the PC attaches.
    assert send('F '+usb(1,status_payload()).hex()) == 'RESULT 0'
    with socket.create_connection(('127.0.0.1',port)) as sock:
        first = read_packets(sock,1)[0]
        assert first[0].type == wp.TYPE_STATUS
        assert len(wp.decode_status(first[1])['nodes']) == 5
        assert send('F '+usb(2,cycle_payload(missing=2)).hex()) == 'RESULT 0'
        header,payload = read_packets(sock,1)[0]
        cycle = wp.decode_csi(payload)
        assert cycle.trigger_seq == 123 and cycle.uart_seq == 45 and not cycle.records[2].valid
        assert cycle.records[0].csi == bytes([0,3])*192
        ack = wp.ACK.pack(1,1,11,1,50000,1000,b'ok')
        send('F '+usb(3,ack).hex())
        assert wp.decode_ack(read_packets(sock,1)[0][1])['message'] == 'ok'
        send('P')
        ph,pp = read_packets(sock,1)[0]
        assert ph.type == wp.TYPE_POSE
        decoded = wp.decode_pose(pp)
        assert decoded.window_id == 7 and decoded.infer_us == 23000
        assert decoded.pose_float()[0] == pytest.approx(-0.12)


def test_raw_csi_is_not_sent_unless_forwarding_is_enabled(start_bridge):
    port,send = start_bridge(forward_csi=False)
    with socket.create_connection(('127.0.0.1',port)) as sock:
        time.sleep(0.03)
        assert send('F '+usb(2,cycle_payload()).hex()) == 'RESULT 0'
        send('P')
        assert read_packets(sock,1)[0][0].type == wp.TYPE_POSE


def test_checksum_and_malformed_cycle_are_not_forwarded(start_bridge):
    port,send = start_bridge(forward_csi=True)
    with socket.create_connection(('127.0.0.1',port)) as sock:
        time.sleep(0.03)
        assert send('F '+usb(2,cycle_payload(),corrupt=True).hex()) == 'RESULT 99'
        bad = bytearray(cycle_payload()); bad[29] = 1
        assert send('F '+usb(2,bad).hex()) == 'RESULT -1'
        sock.settimeout(0.1)
        with pytest.raises(socket.timeout): sock.recv(1)
        send('F '+usb(2,cycle_payload()).hex())
        assert wp.decode_csi(read_packets(sock,1)[0][1]).received_nodes == 5


def test_real_backend_ps_location_confirmation_and_pose(start_bridge):
    port,send = start_bridge(forward_csi=False, location=True)
    service = BackendService(Settings(ps_host='127.0.0.1',ps_port=port,monitor_interval_s=0.01))
    service.start()
    try:
        until(lambda: service._link.connected)
        send('F '+usb(1,status_payload()).hex())
        snap = until(lambda: service.snapshot() if service.snapshot()['system']['status_ready'] else None)
        assert service.confirm_rx_layout(snap['system']['rx_signature'])['ok']
        until(lambda: service.snapshot()['system']['identity_confirmed'])
        send('P')
        snap = until(lambda: service.snapshot() if service.snapshot()['pose']['valid'] else None)
        assert len(snap['pose']['joints']) == 12 and snap['pose']['infer_ms'] == 23
        # Location is computed by the C engine inside the bridge (PS side).
        for seq in range(200,236):   # >= 3 PS windows for LocationStabilizer
            send('F '+usb(2,cycle_payload(seq=seq),seq=seq).hex())
            time.sleep(0.10)
        live_snap = until(lambda: service.snapshot() if service.snapshot()['location']['valid'] else None)
        assert live_snap['location']['point_id'] in {f'p{i:02d}' for i in range(1,11)} | {'empty'}
        assert live_snap['person']['valid']
        assert service._link.snapshot()['counts']['location_packets'] >= 1
        until(lambda: not service.snapshot()['location']['valid'],timeout=4)
    finally:
        link = service._link
        service.stop()
        assert not link._thread.is_alive()
        assert link.latest_pose() is None and link.latest_location() is None


def test_slow_client_resets_and_reconnects_with_cached_status(start_bridge):
    port,send = start_bridge(forward_csi=True)
    send('F '+usb(1,status_payload()).hex())
    with socket.create_connection(('127.0.0.1',port)) as slow:
        read_packets(slow,1)
        time.sleep(0.03)
        started = time.monotonic()
        send('B '+cycle_payload(large=True).hex())
        assert time.monotonic()-started < 1
        slow.settimeout(3)
        while slow.recv(65536): pass
    with socket.create_connection(('127.0.0.1',port)) as new:
        assert read_packets(new,1)[0][0].type == wp.TYPE_STATUS
        send('F '+usb(2,cycle_payload(seq=200)).hex())
        assert wp.decode_csi(read_packets(new,1)[0][1]).trigger_seq == 200


def test_python_receivers_reconnect_and_drop_cached_state(start_bridge):
    port,send = start_bridge(forward_csi=True)
    events = []
    inp = EthernetInput('127.0.0.1',port,lambda row:None,lambda kind,payload:events.append(kind),retry_s=0.01)
    inp.start()
    try:
        until(lambda:inp.snapshot()['connected'])
        send('F '+usb(1,status_payload()).hex())
        until(lambda:'status' in events)
        send('B '+cycle_payload(large=True).hex())
        until(lambda:inp.snapshot()['counts']['connections'] >= 2)
        assert 'closed' in events
        until(lambda:inp.snapshot()['counts']['status_packets'] >= 2)
    finally:
        inp.stop()
        assert not inp._thread.is_alive()
