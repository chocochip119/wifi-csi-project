#!/usr/bin/env python3
import argparse
import socket
import struct
import time

HEADER = struct.Struct("<4sBBBBIQIBBBbHQ")
MAGIC = b"WCSI"
TYPE_CSI = 1
TYPE_POSE = 2

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--quiet-csi", action="store_true")
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.bind, args.port))
    print(f"listening UDP {args.bind}:{args.port}")

    last_packet_seq = None
    total = 0
    csi_count = 0
    pose_count = 0
    gaps = 0
    start = time.time()

    while True:
        data, addr = sock.recvfrom(2048)
        if len(data) < HEADER.size:
            print("short packet", len(data), addr)
            continue

        (magic, version, ptype, rx_id, window_pos,
         packet_seq, window_seq, trigger_seq,
         present_mask, active_nodes, received_nodes, rssi,
         payload_len, timestamp_ns) = HEADER.unpack_from(data)

        if magic != MAGIC or version != 1:
            print("bad header", magic, version)
            continue

        payload = data[HEADER.size:HEADER.size + payload_len]
        if len(payload) != payload_len:
            print("truncated payload", packet_seq, len(payload), payload_len)
            continue

        if last_packet_seq is not None:
            expected = (last_packet_seq + 1) & 0xffffffff
            if packet_seq != expected:
                gap = (packet_seq - expected) & 0xffffffff
                gaps += gap
                print(f"PACKET_GAP expected={expected} got={packet_seq} gap={gap}")
        last_packet_seq = packet_seq
        total += 1

        if ptype == TYPE_CSI:
            csi_count += 1
            if not args.quiet_csi:
                print(
                    f"CSI pkt={packet_seq} win={window_seq} pos={window_pos} "
                    f"trigger={trigger_seq} rx={rx_id} rssi={rssi} "
                    f"present=0x{present_mask:02x} active={active_nodes} "
                    f"received={received_nodes} bytes={payload_len}"
                )
        elif ptype == TYPE_POSE:
            pose_count += 1
            pose = list(struct.unpack(f"<{payload_len}b", payload))
            print(
                f"POSE pkt={packet_seq} win={window_seq} trigger={trigger_seq} "
                f"active={active_nodes} received={received_nodes} pose={pose}"
            )
        else:
            print("unknown type", ptype, "packet", packet_seq)

        if total % 1000 == 0:
            elapsed = max(time.time() - start, 1e-9)
            print(
                f"STATS total={total} csi={csi_count} pose={pose_count} "
                f"seq_gaps={gaps} rate={total/elapsed:.1f} pkt/s"
            )

if __name__ == "__main__":
    main()
