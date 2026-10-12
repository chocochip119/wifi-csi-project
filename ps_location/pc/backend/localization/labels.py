"""One label contract for presence + nine nominal positions + p05 seated (centimetres).

Empty is a class, never a fabricated coordinate or a substitute for missing CSI.
p10 is a posture class: a person seated on the chair at p05. It shares p05's
nominal coordinate, so coordinate error cannot separate p05 from p10; use the
confusion matrix for that. Class order is the deterministic tie-break order.
"""

EMPTY_LABEL = 'empty'
EMPTY_PERSON = 'none'
LOCATION_CLASSES = ('p01', 'p02', 'p03', 'p04', 'p05', 'p06', 'p07', 'p08', 'p09', 'p10')
CLASSES = LOCATION_CLASSES + (EMPTY_LABEL,)
POINTS_CM = {
    'p01': [30, 30], 'p02': [90, 30], 'p03': [150, 30],
    'p04': [30, 90], 'p05': [90, 90], 'p06': [150, 90],
    'p07': [30, 150], 'p08': [90, 150], 'p09': [150, 150],
    'p10': [90, 90],
}
SEATED_LABELS = {'p10': 'p05 앉기'}
TASK = 'presence_and_ninepoint_plus_p05_seated_location'


def display_name(label):
    """GUI/report text; keeps the stored label unchanged."""
    return f"{label}({SEATED_LABELS[label]})" if label in SEATED_LABELS else label
