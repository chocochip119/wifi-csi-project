"""Validate the editable pose_cnn_ctrl target-design diagrams without dependencies.

Usage: python validate_pose_cnn_ctrl_drawio.py [path/to/pose_cnn_ctrl_fsm.drawio]
This reads the draw.io file only; it never changes the design or RTL.
"""

from __future__ import annotations

import html
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET


STATES = (
    "IDLE", "DECODE", "LD_RD1", "LD_RD2", "LD_WAIT", "IN_RD", "ENC",
    "FC1", "FC2", "FC3", "WR", "ERR_DRAIN", "FINISH",
)
CODES = {state: f"{number:04b}" for number, state in enumerate(STATES)}
PAGES = {
    "fsm": ("FSM 상태도", STATES),
    "common": ("ASM - 공통", ("IDLE", "DECODE", "FINISH", "ERR_DRAIN")),
    "load": ("ASM - LOAD", ("LD_RD1", "LD_RD2", "LD_WAIT")),
    "infer": ("ASM - INFER", ("IN_RD", "ENC", "FC1", "FC2", "FC3", "WR")),
}
TRANSITIONS = {
    "t01": ("IDLE", "DECODE"),
    "t03": ("DECODE", "FINISH"),
    "t04": ("DECODE", "FINISH"),
    "t05": ("DECODE", "LD_RD1"),
    "t06": ("DECODE", "IN_RD"),
    "t07": ("LD_RD1", "LD_RD2"),
    "t08": ("LD_RD2", "LD_WAIT"),
    "t09": ("LD_WAIT", "FINISH"),
    "t10": ("IN_RD", "ENC"),
    "t11": ("ENC", "FC1"),
    "t12": ("FC1", "FC2"),
    "t13": ("FC2", "FC3"),
    "t14": ("FC3", "WR"),
    "t15": ("WR", "FINISH"),
    "t16a": ("LD_RD1", "ERR_DRAIN"),
    "t16b": ("LD_RD2", "ERR_DRAIN"),
    "t16c": ("IN_RD", "ERR_DRAIN"),
    "t16d": ("FC1", "ERR_DRAIN"),
    "t17": ("ERR_DRAIN", "FINISH"),
    "t18": ("FINISH", "IDLE"),
}


def plain(value: str) -> str:
    """Treat draw.io HTML labels and plain labels uniformly."""
    value = html.unescape(value)
    value = re.sub(r"<br\s*/?>|</(?:div|p|tr)>", "\n", value, flags=re.I)
    return re.sub(r"<[^>]+>", " ", value)


def compact(value: str) -> str:
    return re.sub(r"\s+|`", "", plain(value))


def style_map(cell: ET.Element) -> dict[str, str]:
    return dict(part.split("=", 1) for part in cell.get("style", "").split(";") if "=" in part)


def validate(path: Path) -> int:
    failures: list[str] = []
    checks = 0

    def check(condition: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        if not condition:
            failures.append(message)

    try:
        document = ET.parse(path)
    except (OSError, ET.ParseError) as exc:
        print(f"FAIL: cannot parse {path}: {exc}")
        return 1

    root = document.getroot()
    check(root.tag == "mxfile", "Root element must be mxfile")
    diagrams = root.findall("diagram")
    check(len(diagrams) == 4, "Expected exactly four diagram pages")
    check([page.get("id") for page in diagrams] == list(PAGES), "Page IDs/order must be fsm, common, load, infer")
    all_text = []
    text_by_page: dict[str, str] = {}
    asm_state_texts: dict[tuple[str, str], str] = {}
    pages_by_id: dict[str, dict[str, ET.Element]] = {}
    summaries = []

    for page in diagrams:
        page_id = page.get("id", "")
        if page_id not in PAGES:
            check(False, f"Unexpected page ID: {page_id!r}")
            continue
        expected_title, expected_states = PAGES[page_id]
        check(page.get("name") == expected_title, f"{page_id}: unexpected page title")
        models = page.findall("mxGraphModel")
        check(len(models) == 1, f"{page_id}: exactly one direct, uncompressed mxGraphModel required")
        check(not (page.text or "").strip(), f"{page_id}: diagram contains encoded/text payload")
        if len(models) != 1:
            continue
        cells = models[0].findall("./root/mxCell")
        ids = [cell.get("id", "") for cell in cells]
        check(all(ids), f"{page_id}: cell missing ID")
        check(len(ids) == len(set(ids)), f"{page_id}: duplicate cell IDs")
        cell_map = {cell.get("id", ""): cell for cell in cells}
        pages_by_id[page_id] = cell_map
        edges = [cell for cell in cells if cell.get("edge") == "1"]
        found_states = {cell_id.removeprefix(f"{page_id}_state_") for cell_id in ids if cell_id.startswith(f"{page_id}_state_")}
        check(found_states == set(expected_states), f"{page_id}: state set differs: {sorted(found_states)}")
        endpoint_ids: set[str] = set()

        for edge in edges:
            for endpoint in ("source", "target"):
                endpoint_id = edge.get(endpoint)
                check(endpoint_id in cell_map, f"{page_id}/{edge.get('id')}: missing or invalid {endpoint}={endpoint_id!r}")
                if endpoint_id in cell_map:
                    endpoint_ids.add(endpoint_id)

        for state in expected_states:
            state_id = f"{page_id}_state_{state}"
            code_id = f"{page_id}_code_{state}"
            state_cell = cell_map.get(state_id)
            code_cell = cell_map.get(code_id)
            check(state_cell is not None and state_cell.get("vertex") == "1", f"{page_id}: {state} is not a vertex")
            check(state_id in endpoint_ids, f"{page_id}: unconnected state {state}")
            check(code_cell is not None, f"{page_id}: missing code label for {state}")
            if code_cell is not None:
                check(code_cell.get("parent") == state_id, f"{page_id}: code label is not child of {state}")
                check(re.search(rf"(?<![01]){CODES[state]}(?![01])", plain(code_cell.get("value", ""))) is not None,
                      f"{page_id}: incorrect 4-bit code for {state}; expected {CODES[state]}")
            if state == "ERR_DRAIN" and state_cell is not None:
                check(style_map(state_cell).get("dashed") == "1", f"{page_id}: ERR_DRAIN must have a dashed border (D08)")
            if page_id != "fsm" and state_cell is not None:
                state_labels = [state_cell.get("value", "")]
                descendants = {state_id}
                while True:
                    additions = {cell_id for cell_id, cell in cell_map.items()
                                 if cell.get("parent") in descendants and cell_id not in descendants}
                    if not additions:
                        break
                    descendants.update(additions)
                    state_labels.extend(cell_map[cell_id].get("value", "") for cell_id in additions)
                state_text = compact("\n".join(state_labels))
                asm_state_texts[(page_id, state)] = state_text
                for pulse in ("loader_start", "mem_rd_start", "enc_start", "fc_start", "mem_wr_start", "snapshot"):
                    check(pulse not in state_text, f"{page_id}/{state}: {pulse} belongs on a transition conditional-output box")

        labels = "\n".join(plain(cell.get("value", "")) for cell in cells)
        all_text.append(labels)
        text_by_page[page_id] = compact(labels)
        check("미결" in labels, f"{page_id}: missing unresolved-item legend")
        check("목표 설계 도면" in labels, f"{page_id}: missing target-design legend")
        logical_count = len(TRANSITIONS) if page_id == "fsm" else sum(source in expected_states for source, _ in TRANSITIONS.values())
        summaries.append((page_id, expected_title, len(found_states), len(edges), logical_count))

    fsm_cells = pages_by_id.get("fsm", {})
    fsm_all_edges = {cell_id: cell for cell_id, cell in fsm_cells.items() if cell.get("edge") == "1"}
    fsm_state_ids = {f"fsm_state_{state}" for state in STATES}
    fsm_edges = {cell_id: cell for cell_id, cell in fsm_all_edges.items()
                 if cell.get("source") in fsm_state_ids and cell.get("target") in fsm_state_ids}
    check(set(fsm_edges) == {f"fsm_{transition}" for transition in TRANSITIONS}, "FSM must have exactly the 20 expected inter-state arrows; no self-loop")
    reset_edges = {cell_id: cell for cell_id, cell in fsm_all_edges.items() if cell_id not in fsm_edges}
    check(set(reset_edges) == {"fsm_reset_edge"}, "FSM must have exactly one additional reset annotation arrow")
    reset_edge = reset_edges.get("fsm_reset_edge")
    if reset_edge is not None:
        check(reset_edge.get("source") == "fsm_reset" and reset_edge.get("target") == "fsm_state_IDLE",
              "Reset annotation arrow must enter IDLE")
    for transition, (source, target) in TRANSITIONS.items():
        edge = fsm_edges.get(f"fsm_{transition}")
        if edge is None:
            continue
        check(edge.get("source") == f"fsm_state_{source}" and edge.get("target") == f"fsm_state_{target}",
              f"{transition}: expected {source} -> {target}")
        if transition.startswith("t16") or transition == "t17":
            check(style_map(edge).get("dashed") == "1", f"{transition}: D08 transition must be dashed")

    combined = compact("\n".join(all_text))
    required = {
        "corrected FC1 write enable": "fifo_we=mem_rd_valid&&!fifo_full",
        "FC1 backpressure": "mem_rd_ready=!fifo_full",
        "FC1 data route": "fifo_wdata=mem_rd_data",
        "input write enable retained": "in_we=mem_rd_valid",
        "Loader valid route retained": "ld_valid=mem_rd_valid",
        "D06 unresolved": "D06",
        "D08 unresolved": "D08",
        "START snapshot": "snapshot",
        "command snapshot field": "cmd",
        "input address snapshot field": "input_addr",
        "weight address snapshot field": "weight_addr",
        "output address snapshot field": "output_addr",
        "done update": "status_done",
        "error update": "status_error",
        "clear status": "reg_clear_status",
        "D02 clear rule": "R1",
        "D02 record rule": "R2",
        "D02 clear-preserves-execution rule": "R3",
        "D02 arbitration rule": "R4",
        "current implementation reference": "PROJECT_CONTEXT.md8절참조",
    }
    for description, fragment in required.items():
        check(fragment in combined, f"Missing required label: {description} ({fragment})")
    check("현재구현됨" not in combined, "Do not label target states as currently implemented")
    for page_id, state, equations in (
        ("infer", "FC1", ("fifo_we=mem_rd_valid&&!fifo_full", "mem_rd_ready=!fifo_full", "fifo_wdata=mem_rd_data")),
        ("infer", "IN_RD", ("in_we=mem_rd_valid",)),
        ("load", "LD_RD1", ("ld_valid=mem_rd_valid",)),
        ("load", "LD_RD2", ("ld_valid=mem_rd_valid",)),
    ):
        for equation in equations:
            check(equation in asm_state_texts.get((page_id, state), ""),
                  f"{page_id}/{state}: missing required state-level equation {equation}")

    common_text = text_by_page.get("common", "")
    check("기록>해제" in common_text or "기록우선" in common_text or "기록이우선" in common_text,
          "Common ASM must state that result recording takes priority over clearing")
    check("다른edge" in common_text or "서로다른" in common_text or "다른에지" in common_text,
          "Common ASM must explain R1 and R2 occur on different edges")
    check("불변" in common_text or "유지" in common_text,
          "Common ASM must mention CLEAR preserves execution/internal error")

    print(f"File: {path.resolve()}")
    print("Page | states | drawn edge segments | logical inter-state transitions")
    for page_id, title, state_count, edge_count, logical_count in summaries:
        print(f"{page_id} ({title}) | {state_count} | {edge_count} | {logical_count}")
    print("FSM logical transitions: 20 (original numbered items 1, 3-18; item 16 expanded into four arrows; item 2 self-loop omitted).")
    print("FSM drawn segments: 21 = 20 inter-state arrows + 1 reset annotation arrow.")
    print("ASM logical counts are assigned by source-state ownership; drawn segments include decisions, conditional outputs, and wait paths.")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        print(f"RESULT: FAIL ({len(failures)} failures / {checks} checks)")
        return 1
    print(f"RESULT: PASS ({checks} checks)")
    print("Scope: XML structure and selected content contracts only; visual layout and RTL behavior are reviewed separately.")
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("pose_cnn_ctrl_fsm.drawio")
    raise SystemExit(validate(target))
