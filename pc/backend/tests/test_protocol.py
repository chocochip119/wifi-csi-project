import struct
import pytest
from protocol import wise_protocol as wp
from localization.ethernet_input import StreamDecoder, cycle_rows, ClockMapper


def sample_cycle():
    return wp.CsiCycle(123, 45, 5, 4, True,
        [wp.RxRecord(i, i != 2, -40-i, bytes([i, 1])*192 if i != 2 else b'') for i in range(5)])


def test_fragmented_and_coalesced_stream_preserves_missing_rx():
    cycle = sample_cycle()
    encoded = wp.frame(wp.TYPE_CSI, wp.encode_csi(cycle), 0xffffffff, 500000)
    decoder = StreamDecoder()
    packets = []
    for byte in encoded: packets.extend(decoder.feed(bytes([byte])))
    packets.extend(decoder.feed(encoded + encoded))
    assert len(packets) == 3 and not decoder.buffer
    decoded = wp.decode_csi(packets[0][1])
    assert decoded == cycle
    assert [r['rx_index'] for r in cycle_rows(decoded, 11, 2)] == [0, 1, 3, 4]


@pytest.mark.parametrize('field,value', [('version',1),('magic',b'WCSI'),('size',99999),('type',9)])
def test_reject_wrong_wire_header(field, value):
    data = [wp.MAGIC, wp.VERSION, 1, 24, 10, 1, 2]
    data[{'magic':0,'version':1,'type':2,'size':4}[field]] = value
    with pytest.raises(wp.ProtocolError): wp.unpack_header(wp.HEADER.pack(*data))


@pytest.mark.parametrize('scale', [0, -0.1, float('nan'), float('inf')])
def test_reject_invalid_pose_scale(scale):
    data = wp.POSE.pack(1, 2, 3, scale, *range(24))
    with pytest.raises(wp.ProtocolError): wp.decode_pose(data)


@pytest.mark.parametrize('case', ['duplicate','odd','received','mask','active','trailing'])
def test_reject_inconsistent_cycles(case):
    data = bytearray(wp.encode_csi(sample_cycle()))
    if case == 'duplicate': data[16+8+384] = 0
    if case == 'odd': struct.pack_into('<H',data,20,383)
    if case == 'received': data[9] = 5
    if case == 'mask': data[11] = 31
    if case == 'active': data[8] = 4
    if case == 'trailing': data += b'x'
    with pytest.raises(wp.ProtocolError): wp.decode_csi(data)


def test_clock_spacing_floor_and_reconnect():
    clock = ClockMapper()
    assert clock.map(100,1000000) == 1000000
    assert clock.map(200,1150000) == 1100000
    clock.set_floor(1200000)
    assert clock.map(300,1300000) > 1200000
    clock.reset()
    assert clock.map(1,5000000) == 5000000
