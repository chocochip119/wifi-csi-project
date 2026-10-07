from pathlib import Path
import queue
import socket
import struct
import subprocess
import threading
import time
import pytest
from protocol import wise_protocol as wp
from localization.ethernet_input import StreamDecoder, EthernetInput, PoseInput
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


def free_ports():
    sockets = [socket.socket(),socket.socket()]
    try:
        for s in sockets: s.bind(('127.0.0.1',0))
        return [s.getsockname()[1] for s in sockets]
    finally:
        for s in sockets: s.close()


@pytest.fixture(scope='session')
def bridge_binary(tmp_path_factory):
    binary = tmp_path_factory.mktemp('cbridge')/'server'
    subprocess.run(['gcc','-std=c11','-Wall','-Wextra','-Werror','-pthread',
        '-I'+str(ROOT/'ps/include'),str(ROOT/'ps/tests/wise_test_server.c'),
        str(ROOT/'ps/src/wise_server.c'),str(ROOT/'ps/src/csi_pipeline.c'),'-lm','-o',str(binary)],check=True)
    return binary


@pytest.fixture
def bridge(bridge_binary):
    ports = free_ports()
    proc = subprocess.Popen([str(bridge_binary),*map(str,ports)],stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    replies = queue.Queue()
    def reader():
        for line in proc.stdout: replies.put(line.strip())
    threading.Thread(target=reader,daemon=True).start()
    assert replies.get(timeout=3) == 'READY'
    def send(command):
        proc.stdin.write(command+'\n'); proc.stdin.flush()
        return replies.get(timeout=3)
    yield ports, send
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


def test_c_usb_parser_tcp_framing_status_ack_csi_and_pose(bridge):
    ports,send = bridge
    # Cache validated STATUS even before the PC attaches.
    assert send('F '+usb(1,status_payload()).hex()) == 'RESULT 0'
    with socket.create_connection(('127.0.0.1',ports[0])) as csi, socket.create_connection(('127.0.0.1',ports[1])) as pose:
        first = read_packets(csi,1)[0]
        assert first[0].type == wp.TYPE_STATUS
        assert len(wp.decode_status(first[1])['nodes']) == 5
        assert send('F '+usb(2,cycle_payload(missing=2)).hex()) == 'RESULT 0'
        header,payload = read_packets(csi,1)[0]
        cycle = wp.decode_csi(payload)
        assert cycle.trigger_seq == 123 and cycle.uart_seq == 45 and not cycle.records[2].valid
        assert cycle.records[0].csi == bytes([0,3])*192
        ack = wp.ACK.pack(1,1,11,1,50000,1000,b'ok')
        send('F '+usb(3,ack).hex())
        assert wp.decode_ack(read_packets(csi,1)[0][1])['message'] == 'ok'
        # Wait until PoseInput/worker has accepted before publishing a transient pose.
        time.sleep(0.03)
        send('P')
        ph,pp = read_packets(pose,1)[0]
        assert ph.type == wp.TYPE_POSE
        decoded = wp.decode_pose(pp)
        assert decoded.window_id == 7 and decoded.infer_us == 23000
        assert decoded.pose_float()[0] == pytest.approx(-0.12)


def test_checksum_and_malformed_cycle_are_not_forwarded(bridge):
    ports,send = bridge
    with socket.create_connection(('127.0.0.1',ports[0])) as sock:
        time.sleep(0.03)
        assert send('F '+usb(2,cycle_payload(),corrupt=True).hex()) == 'RESULT 99'
        bad = bytearray(cycle_payload()); bad[29] = 1
        assert send('F '+usb(2,bad).hex()) == 'RESULT -1'
        sock.settimeout(0.1)
        with pytest.raises(socket.timeout): sock.recv(1)
        send('F '+usb(2,cycle_payload()).hex())
        assert wp.decode_csi(read_packets(sock,1)[0][1]).received_nodes == 5


def test_real_backend_status_confirmation_and_pose_disconnect(bridge):
    ports,send = bridge
    service = BackendService(Settings(ps_host='127.0.0.1',csi_port=ports[0],pose_port=ports[1],monitor_interval_s=0.01))
    service.start()
    try:
        until(lambda: service._live.serial.snapshot()['connected'] and service._pose.connected)
        send('F '+usb(1,status_payload()).hex())
        until(lambda: service._live.serial.snapshot()['status'])
        assert service.confirm_rx_layout()['ok']
        until(lambda: service.snapshot()['system']['identity_confirmed'])
        send('F '+usb(1,status_payload()).hex())
        until(lambda: service.snapshot()['system']['status_ready'])
        send('P')
        snap = until(lambda: service.snapshot() if service.snapshot()['pose']['valid'] else None)
        assert len(snap['pose']['joints']) == 12 and snap['pose']['infer_ms'] == 23
        for seq in range(200,228):
            send('F '+usb(2,cycle_payload(seq=seq),seq=seq).hex())
            time.sleep(0.10)
        live_snap = until(lambda: service.snapshot() if service.snapshot()['location']['valid'] else None)
        assert live_snap['location']['point_id'] in {f'p{i:02d}' for i in range(1,11)} | {'empty'}
        assert live_snap['person']['valid']
        until(lambda: not service.snapshot()['location']['valid'],timeout=4)
    finally:
        pose_input = service._pose
        service.stop()
        assert not pose_input._thread.is_alive()
        assert pose_input.latest_pose() is None


def test_slow_csi_client_resets_without_blocking_pose_and_reconnects(bridge):
    ports,send = bridge
    send('F '+usb(1,status_payload()).hex())
    with socket.create_connection(('127.0.0.1',ports[0])) as slow, socket.create_connection(('127.0.0.1',ports[1])) as pose:
        read_packets(slow,1)
        time.sleep(0.03)
        started = time.monotonic()
        send('B '+cycle_payload(large=True).hex())
        assert time.monotonic()-started < 1
        send('P')
        assert wp.decode_pose(read_packets(pose,1)[0][1]).window_id == 7
        slow.settimeout(3)
        while slow.recv(65536): pass
    with socket.create_connection(('127.0.0.1',ports[0])) as new:
        assert read_packets(new,1)[0][0].type == wp.TYPE_STATUS
        send('F '+usb(2,cycle_payload(seq=200)).hex())
        assert wp.decode_csi(read_packets(new,1)[0][1]).trigger_seq == 200


def test_python_receivers_reconnect_and_drop_cached_state(bridge):
    ports,send = bridge
    events = []
    inp = EthernetInput('127.0.0.1',ports[0],lambda row:None,lambda kind,payload:events.append(kind),retry_s=0.01)
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
