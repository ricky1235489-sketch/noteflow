"""左手伴奏型態產生器。

提供多種鋼琴左手伴奏模式，根據偵測到的和弦與音樂特徵自適應產生。

靈感來源：NicePianoSheet 風格 — 段落動態對比鮮明，
verse 簡潔（八度根音/分解和弦），chorus 飽滿（power octave + 和弦填充），
過渡段用十六分音符 fill，結尾琶音漸慢。

伴奏型態：
- Block chords: 穩定和聲基礎，適合慢歌抒情段
- Alberti bass: 古典風格流動感 (低-高-中-高)
- Broken chord: 流行鋼琴最常用的分解和弦
- Arpeggio: 浪漫風格，跨八度琶音
- Stride: 爵士/搖擺風格，低音與和弦大跳
- Walking bass: 爵士風格，半音階行進低音
- Oom-pah: 進行曲/圓舞曲風格，根音+和弦交替
- Ostinato: 重複節奏型態，營造張力
- Power octave: NicePianoSheet 風格副歌，八度低音+和弦填充
- Tremolo chord: 震音和弦，高潮段落
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import pretty_midi

from .chord_detector import Chord, CHORD_TEMPLATES


class PatternType(Enum):
    """伴奏型態類型。"""
    BROKEN_CHORD = "broken_chord"
    ALBERTI_BASS = "alberti_bass"
    OCTAVE_ROOT = "octave_root"
    BLOCK_CHORD = "block_chord"
    ARPEGGIO_UP = "arpeggio_up"
    ROOT_FIFTH = "root_fifth"
    STRIDE = "stride"
    WALKING_BASS = "walking_bass"
    OOM_PAH = "oom_pah"
    OSTINATO = "ostinato"
    POWER_OCTAVE = "power_octave"
    TREMOLO_CHORD = "tremolo_chord"
    ADAPTIVE = "adaptive"


DEFAULT_OCTAVE = 3
DEFAULT_VELOCITY = 65

# ─── 段落位置常數 ───
INTRO_RATIO = 0.08
OUTRO_RATIO = 0.92
CHORUS_VELOCITY_THRESHOLD = 75
CHORUS_DENSITY_THRESHOLD = 2.0


@dataclass(frozen=True)
class NoteEvent:
    """單一音符事件。"""
    pitch: int
    start: float
    end: float
    velocity: int = DEFAULT_VELOCITY


@dataclass(frozen=True)
class MeasureContext:
    """小節的音樂特徵，用於自適應選擇。"""
    measure_index: int
    note_density: float    # 每拍音符數
    avg_velocity: float    # 平均力度
    pitch_range: int       # 音域跨度（半音）
    has_sustained: bool    # 是否有長音符
    tempo: float
    is_first_measure: bool
    is_last_measure: bool
    total_measures: int
    prev_density: float = 0.0    # 前一小節密度（偵測段落變化）
    prev_velocity: float = 0.0   # 前一小節力度


class ArrangementPatterns:
    """根據和弦與音樂特徵自適應產生左手伴奏。

    NicePianoSheet 風格核心理念：
    1. 段落對比 — verse 簡潔，chorus 飽滿，bridge 變化
    2. 動態漸進 — 不突然切換，用 velocity 漸變過渡
    3. 八度低音是骨架 — 幾乎所有段落都以八度根音為基礎
    4. 填充音增加豐富度 — 和弦音在拍間穿插
    5. 過渡段用十六分音符 fill 銜接
    """

    def generate(
        self,
        chords: list[Chord],
        pattern: PatternType = PatternType.ADAPTIVE,
        tempo: float = 120.0,
        beats_per_measure: int = 4,
        octave: int = DEFAULT_OCTAVE,
        velocity: int = DEFAULT_VELOCITY,
        right_hand_notes: list | None = None,
    ) -> list[NoteEvent]:
        """產生整首曲子的左手伴奏。"""
        all_events: list[NoteEvent] = []
        seconds_per_beat = 60.0 / tempo

        contexts = self._analyze_contexts(
            chords, right_hand_notes, tempo, beats_per_measure,
        )

        prev_pattern = None
        for i, chord in enumerate(chords):
            ctx = contexts[i] if i < len(contexts) else None

            if pattern == PatternType.ADAPTIVE:
                chosen = self._choose_pattern(ctx, chord, prev_pattern)
            else:
                chosen = pattern

            # 段落過渡時微調 velocity（NicePianoSheet 風格漸變）
            adjusted_velocity = self._adjust_velocity(velocity, ctx)

            generator = self._get_generator(chosen)
            events = generator(
                chord, seconds_per_beat, beats_per_measure,
                octave, adjusted_velocity, ctx,
            )
            all_events = [*all_events, *events]
            prev_pattern = chosen

        return all_events

    def _adjust_velocity(self, base_velocity: int, ctx: MeasureContext | None) -> int:
        """根據段落位置微調力度，模擬自然演奏的動態變化。"""
        if ctx is None:
            return base_velocity

        ratio = ctx.measure_index / max(ctx.total_measures - 1, 1)

        # 開頭漸入
        if ratio < INTRO_RATIO:
            return max(40, base_velocity - 15)

        # 結尾漸出
        if ratio > OUTRO_RATIO:
            fade = int((ratio - OUTRO_RATIO) / (1.0 - OUTRO_RATIO) * 20)
            return max(35, base_velocity - fade)

        # 高密度段落（副歌）加強
        if ctx.avg_velocity > CHORUS_VELOCITY_THRESHOLD:
            return min(100, base_velocity + 10)

        return base_velocity

    def _get_generator(self, pattern: PatternType):
        generators = {
            PatternType.BROKEN_CHORD: self._broken_chord,
            PatternType.ALBERTI_BASS: self._alberti_bass,
            PatternType.OCTAVE_ROOT: self._octave_root,
            PatternType.BLOCK_CHORD: self._block_chord,
            PatternType.ARPEGGIO_UP: self._arpeggio_up,
            PatternType.ROOT_FIFTH: self._root_fifth,
            PatternType.STRIDE: self._stride,
            PatternType.WALKING_BASS: self._walking_bass,
            PatternType.OOM_PAH: self._oom_pah,
            PatternType.OSTINATO: self._ostinato,
            PatternType.POWER_OCTAVE: self._power_octave,
            PatternType.TREMOLO_CHORD: self._tremolo_chord,
        }
        return generators.get(pattern, self._broken_chord)


    # ─── 段落分析與自適應選擇 ───

    def _analyze_contexts(
        self,
        chords: list[Chord],
        right_hand_notes: list | None,
        tempo: float,
        beats_per_measure: int,
    ) -> list[MeasureContext]:
        """分析每小節的音樂特徵，含前一小節資訊用於偵測段落變化。"""
        total = len(chords)
        contexts: list[MeasureContext] = []
        prev_density = 0.0
        prev_velocity = 0.0

        for i, chord in enumerate(chords):
            rh_notes = self._get_rh_notes_in_range(
                right_hand_notes, chord.start_time, chord.end_time,
            )
            density = len(rh_notes) / max(beats_per_measure, 1)
            avg_vel = (
                sum(n.velocity for n in rh_notes) / len(rh_notes)
                if rh_notes else 70
            )
            pitches = [n.pitch for n in rh_notes] if rh_notes else [60]
            pitch_range = max(pitches) - min(pitches) if len(pitches) > 1 else 0
            has_sustained = any(
                (n.end - n.start) > (60.0 / tempo * 2) for n in rh_notes
            )

            contexts.append(MeasureContext(
                measure_index=i,
                note_density=density,
                avg_velocity=avg_vel,
                pitch_range=pitch_range,
                has_sustained=has_sustained,
                tempo=tempo,
                is_first_measure=(i == 0),
                is_last_measure=(i == total - 1),
                total_measures=total,
                prev_density=prev_density,
                prev_velocity=prev_velocity,
            ))
            prev_density = density
            prev_velocity = avg_vel

        return contexts

    def _get_rh_notes_in_range(self, notes, start: float, end: float) -> list:
        if not notes:
            return []
        return [n for n in notes if n.start >= start - 0.01 and n.start < end]

    def _is_section_transition(self, ctx: MeasureContext) -> bool:
        """偵測是否為段落過渡點（密度或力度突然變化）。"""
        density_jump = abs(ctx.note_density - ctx.prev_density) > 1.5
        velocity_jump = abs(ctx.avg_velocity - ctx.prev_velocity) > 15
        return density_jump or velocity_jump

    def _choose_pattern(
        self,
        ctx: MeasureContext | None,
        chord: Chord,
        prev_pattern: PatternType | None = None,
    ) -> PatternType:
        """NicePianoSheet 風格自適應選擇。

        核心策略：
        - Intro (前 8%): 簡潔八度根音或根音+五度
        - Verse (低密度): 分解和弦或 Alberti bass
        - Pre-chorus (密度漸增): oom-pah 或 walking bass 過渡
        - Chorus (高密度+高力度): power octave 或 stride
        - Bridge (變化段): ostinato 或 tremolo
        - Outro (後 8%): 琶音漸慢
        - 段落過渡點: 十六分音符 fill (ostinato)
        """
        if ctx is None:
            return PatternType.BROKEN_CHORD

        tempo = ctx.tempo
        density = ctx.note_density
        velocity = ctx.avg_velocity
        position = ctx.measure_index / max(ctx.total_measures - 1, 1)

        # ── Intro：簡潔開場 ──
        if position < INTRO_RATIO:
            if ctx.is_first_measure:
                return PatternType.ROOT_FIFTH
            return PatternType.OCTAVE_ROOT

        # ── Outro：琶音收尾 ──
        if position > OUTRO_RATIO:
            if ctx.is_last_measure:
                return PatternType.BLOCK_CHORD
            return PatternType.ARPEGGIO_UP

        # ── 段落過渡點：用 fill 銜接 ──
        if self._is_section_transition(ctx):
            return PatternType.OSTINATO

        # ── 慢速抒情 (< 90 BPM) ──
        if tempo < 90:
            if ctx.has_sustained:
                return PatternType.ARPEGGIO_UP
            if velocity > CHORUS_VELOCITY_THRESHOLD:
                return PatternType.POWER_OCTAVE
            return PatternType.OCTAVE_ROOT

        # ── 中慢速 (90-110 BPM) ──
        if tempo < 110:
            if velocity > 80 and density > CHORUS_DENSITY_THRESHOLD:
                return PatternType.POWER_OCTAVE
            if velocity > 75:
                return PatternType.STRIDE
            if density < 1.5:
                return PatternType.ARPEGGIO_UP
            return PatternType.BROKEN_CHORD

        # ── 中速 (110-140 BPM) — 流行歌最常見 ──
        if tempo < 140:
            # 副歌（高力度 + 高密度）
            if velocity > CHORUS_VELOCITY_THRESHOLD and density > CHORUS_DENSITY_THRESHOLD:
                return PatternType.POWER_OCTAVE
            # Pre-chorus 過渡
            if density > ctx.prev_density + 0.5 and velocity > 65:
                return PatternType.OOM_PAH
            # 主歌
            if density < CHORUS_DENSITY_THRESHOLD:
                return PatternType.BROKEN_CHORD
            return PatternType.ALBERTI_BASS

        # ── 快速 (>= 140 BPM) ──
        if velocity > 80 and density > 3.0:
            return PatternType.TREMOLO_CHORD
        if density > 3.0:
            return PatternType.OSTINATO
        if velocity > 80:
            return PatternType.STRIDE
        return PatternType.ALBERTI_BASS


    # ─── 基礎伴奏型態 ───

    def _broken_chord(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """分解和弦：根-三-五-三，流行鋼琴最常用。"""
        pitches = chord.pitches_in_octave(octave)
        if len(pitches) < 3:
            return self._root_fifth(chord, spb, bpm, octave, velocity, ctx)

        sequence = [pitches[0], pitches[1], pitches[2], pitches[1]]
        events: list[NoteEvent] = []
        for i, pitch in enumerate(sequence[:bpm]):
            events = [
                *events,
                NoteEvent(
                    pitch=pitch,
                    start=chord.start_time + i * spb,
                    end=chord.start_time + (i + 0.9) * spb,
                    velocity=velocity - (5 if i % 2 == 1 else 0),
                ),
            ]
        return events

    def _alberti_bass(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """Alberti bass：低-高-中-高，古典風格流動感。"""
        pitches = chord.pitches_in_octave(octave)
        if len(pitches) < 3:
            return self._broken_chord(chord, spb, bpm, octave, velocity, ctx)

        low, mid, high = pitches[0], pitches[1], pitches[2]
        pattern_seq = [low, high, mid, high, low, high, mid, high]
        events: list[NoteEvent] = []
        eighth = spb / 2
        total_eighths = bpm * 2

        for i in range(min(total_eighths, len(pattern_seq))):
            p = pattern_seq[i % len(pattern_seq)]
            events = [
                *events,
                NoteEvent(
                    pitch=p,
                    start=chord.start_time + i * eighth,
                    end=chord.start_time + (i + 0.85) * eighth,
                    velocity=velocity - (8 if i % 2 == 1 else 0),
                ),
            ]
        return events

    def _octave_root(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """八度根音：低八度+高八度根音交替，抒情慢歌骨架。"""
        root_low = (octave + 1) * 12 + chord.root
        root_high = root_low + 12
        events: list[NoteEvent] = []

        # 第一拍：低八度根音（長音）
        events = [
            *events,
            NoteEvent(
                pitch=root_low,
                start=chord.start_time,
                end=chord.start_time + spb * 1.8,
                velocity=velocity,
            ),
        ]
        # 第三拍：高八度根音
        if bpm >= 3:
            events = [
                *events,
                NoteEvent(
                    pitch=root_high,
                    start=chord.start_time + 2 * spb,
                    end=chord.start_time + spb * 3.8,
                    velocity=velocity - 10,
                ),
            ]
        return events

    def _block_chord(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """Block chord：整個和弦同時彈奏，穩定有力。"""
        pitches = chord.pitches_in_octave(octave)
        events: list[NoteEvent] = []

        positions = [0, 2 * spb] if bpm >= 4 else [0]
        for pos in positions:
            start = chord.start_time + pos
            end = start + spb * 1.8
            for p in pitches:
                events = [
                    *events,
                    NoteEvent(
                        pitch=p,
                        start=start,
                        end=min(end, chord.end_time),
                        velocity=velocity,
                    ),
                ]
        return events

    def _arpeggio_up(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """上行琶音：從低到高逐一彈奏，浪漫風格。"""
        pitches = chord.pitches_in_octave(octave)
        high_root = pitches[0] + 12
        arp_pitches = [*pitches, high_root]
        events: list[NoteEvent] = []
        note_dur = spb * bpm / len(arp_pitches)

        for i, p in enumerate(arp_pitches):
            events = [
                *events,
                NoteEvent(
                    pitch=p,
                    start=chord.start_time + i * note_dur,
                    end=chord.start_time + (i + 0.9) * note_dur,
                    velocity=velocity - 5 + i * 2,
                ),
            ]
        return events

    def _root_fifth(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """根音+五度：簡潔有力，適合開場或過渡。"""
        root = (octave + 1) * 12 + chord.root
        fifth = root + 7
        events: list[NoteEvent] = []

        for p in [root, fifth]:
            events = [
                *events,
                NoteEvent(
                    pitch=p,
                    start=chord.start_time,
                    end=chord.start_time + spb * 1.8,
                    velocity=velocity,
                ),
            ]
        if bpm >= 4:
            events = [
                *events,
                NoteEvent(
                    pitch=root,
                    start=chord.start_time + 2 * spb,
                    end=chord.start_time + spb * 3.5,
                    velocity=velocity - 10,
                ),
            ]
        return events


    # ─── 進階伴奏型態 ───

    def _stride(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """Stride：爵士風格，低音根音與高位和弦大跳交替。

        拍 1,3: 低八度根音（或根音+五度）
        拍 2,4: 中高位和弦音群
        """
        root_low = (octave + 1) * 12 + chord.root
        chord_pitches = chord.pitches_in_octave(octave + 1)  # 高一個八度的和弦
        events: list[NoteEvent] = []

        for beat in range(min(bpm, 4)):
            start = chord.start_time + beat * spb
            if beat % 2 == 0:
                # 強拍：低音根音 + 八度
                for p in [root_low, root_low + 12]:
                    events = [
                        *events,
                        NoteEvent(
                            pitch=p,
                            start=start,
                            end=start + spb * 0.85,
                            velocity=velocity,
                        ),
                    ]
            else:
                # 弱拍：高位和弦
                for p in chord_pitches[:3]:
                    events = [
                        *events,
                        NoteEvent(
                            pitch=p,
                            start=start,
                            end=start + spb * 0.75,
                            velocity=velocity - 8,
                        ),
                    ]
        return events

    def _walking_bass(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """Walking bass：爵士風格，每拍一個音，半音階行進。

        根音 → 三度 → 五度 → 經過音（半音趨近下一和弦根音）
        """
        root = (octave + 1) * 12 + chord.root
        pitches = chord.pitches_in_octave(octave)

        # 根音 → 三度 → 五度 → 半音下行趨近
        walk_sequence = [
            pitches[0],
            pitches[1] if len(pitches) > 1 else root + 4,
            pitches[2] if len(pitches) > 2 else root + 7,
            pitches[0] + 12 - 1,  # 半音下行趨近高八度
        ]

        events: list[NoteEvent] = []
        for i in range(min(bpm, len(walk_sequence))):
            events = [
                *events,
                NoteEvent(
                    pitch=walk_sequence[i],
                    start=chord.start_time + i * spb,
                    end=chord.start_time + (i + 0.85) * spb,
                    velocity=velocity - (3 if i % 2 == 1 else 0),
                ),
            ]
        return events

    def _oom_pah(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """Oom-pah：根音在強拍，和弦在弱拍，進行曲/圓舞曲風格。

        4/4: 根音-和弦-根音-和弦
        3/4: 根音-和弦-和弦
        """
        root = (octave + 1) * 12 + chord.root
        chord_pitches = chord.pitches_in_octave(octave)
        events: list[NoteEvent] = []

        for beat in range(min(bpm, 4)):
            start = chord.start_time + beat * spb
            if beat % 2 == 0:
                # Oom: 根音（八度）
                events = [
                    *events,
                    NoteEvent(
                        pitch=root,
                        start=start,
                        end=start + spb * 0.8,
                        velocity=velocity,
                    ),
                ]
            else:
                # Pah: 和弦音群
                for p in chord_pitches[:3]:
                    events = [
                        *events,
                        NoteEvent(
                            pitch=p,
                            start=start,
                            end=start + spb * 0.7,
                            velocity=velocity - 10,
                        ),
                    ]
        return events

    def _ostinato(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """Ostinato：十六分音符重複節奏型態，營造張力與過渡 fill。

        NicePianoSheet 風格：段落過渡時用快速音群銜接。
        根音為主，穿插五度和八度。
        """
        root = (octave + 1) * 12 + chord.root
        fifth = root + 7
        octave_up = root + 12

        # 十六分音符 pattern: 根-根-五-根-八-根-五-根...
        pattern_seq = [root, root, fifth, root, octave_up, root, fifth, root]
        events: list[NoteEvent] = []
        sixteenth = spb / 4
        total_sixteenths = bpm * 4

        for i in range(min(total_sixteenths, 16)):
            p = pattern_seq[i % len(pattern_seq)]
            # 漸強效果（fill 感）
            vel_offset = min(i, 8) * 1
            events = [
                *events,
                NoteEvent(
                    pitch=p,
                    start=chord.start_time + i * sixteenth,
                    end=chord.start_time + (i + 0.8) * sixteenth,
                    velocity=min(100, velocity - 10 + vel_offset),
                ),
            ]
        return events


    # ─── NicePianoSheet 風格特色型態 ───

    def _power_octave(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """Power Octave：NicePianoSheet 副歌招牌。

        強拍八度低音打底 + 弱拍和弦音填充，
        營造飽滿有力的副歌效果。

        結構（4/4）：
        拍1: 八度根音（強）
        拍1.5: 和弦三度音（填充）
        拍2: 和弦五度音（填充）
        拍3: 八度根音（次強）
        拍3.5: 和弦三度音（填充）
        拍4: 和弦五度音（填充）
        """
        root_low = (octave + 1) * 12 + chord.root
        root_high = root_low + 12
        pitches = chord.pitches_in_octave(octave)
        third = pitches[1] if len(pitches) > 1 else root_low + 4
        fifth = pitches[2] if len(pitches) > 2 else root_low + 7
        events: list[NoteEvent] = []

        # 拍 1: 八度根音（強拍）
        for p in [root_low, root_high]:
            events = [
                *events,
                NoteEvent(
                    pitch=p,
                    start=chord.start_time,
                    end=chord.start_time + spb * 0.9,
                    velocity=velocity,
                ),
            ]

        # 拍 1.5: 三度音填充
        events = [
            *events,
            NoteEvent(
                pitch=third,
                start=chord.start_time + spb * 0.5,
                end=chord.start_time + spb * 0.9,
                velocity=velocity - 12,
            ),
        ]

        # 拍 2: 五度音填充
        events = [
            *events,
            NoteEvent(
                pitch=fifth,
                start=chord.start_time + spb,
                end=chord.start_time + spb * 1.85,
                velocity=velocity - 8,
            ),
        ]

        if bpm >= 4:
            # 拍 3: 八度根音（次強拍）
            for p in [root_low, root_high]:
                events = [
                    *events,
                    NoteEvent(
                        pitch=p,
                        start=chord.start_time + 2 * spb,
                        end=chord.start_time + spb * 2.9,
                        velocity=velocity - 5,
                    ),
                ]

            # 拍 3.5: 三度音填充
            events = [
                *events,
                NoteEvent(
                    pitch=third,
                    start=chord.start_time + spb * 2.5,
                    end=chord.start_time + spb * 2.9,
                    velocity=velocity - 15,
                ),
            ]

            # 拍 4: 五度音填充
            events = [
                *events,
                NoteEvent(
                    pitch=fifth,
                    start=chord.start_time + 3 * spb,
                    end=chord.start_time + spb * 3.85,
                    velocity=velocity - 10,
                ),
            ]

        return events

    def _tremolo_chord(
        self, chord: Chord, spb: float, bpm: int,
        octave: int, velocity: int, ctx: MeasureContext | None,
    ) -> list[NoteEvent]:
        """Tremolo Chord：快速交替和弦音，高潮段落的震撼效果。

        將和弦拆成兩組交替快速彈奏（三十二分音符感），
        適合快速激昂段落。
        """
        pitches = chord.pitches_in_octave(octave)
        if len(pitches) < 3:
            return self._power_octave(chord, spb, bpm, octave, velocity, ctx)

        root = pitches[0]
        # 兩組交替：[根音+五度] vs [三度+八度根音]
        group_a = [root, pitches[2]]
        group_b = [pitches[1], root + 12]

        events: list[NoteEvent] = []
        eighth = spb / 2
        total_eighths = bpm * 2

        for i in range(min(total_eighths, 8)):
            group = group_a if i % 2 == 0 else group_b
            start = chord.start_time + i * eighth
            for p in group:
                events = [
                    *events,
                    NoteEvent(
                        pitch=p,
                        start=start,
                        end=start + eighth * 0.8,
                        velocity=velocity - (5 if i % 2 == 1 else 0),
                    ),
                ]
        return events
