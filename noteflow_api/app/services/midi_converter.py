"""MIDI 資料處理：和弦偵測、左右手分離、智慧編排。"""
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import pretty_midi

from .chord_detector import ChordDetector
from .arrangement_patterns import (
    ArrangementPatterns,
    PatternType,
    DEFAULT_OCTAVE,
    DEFAULT_VELOCITY,
)

MIDDLE_C = 60  # MIDI note number for C4


class MidiConverter:
    """MIDI 資料處理：量化、左右手分離、智慧左手編排。"""
    
    # 統一的量化網格設定
    QUANTIZE_GRID = "16th"  # 預設量化到 16 分音符
    
    # 標準音符時值（以 16 分音符為單位）
    STANDARD_DURATIONS = {
        "32nd": 0.5,   # 32 分音符
        "16th": 1.0,   # 16 分音符
        "8th": 2.0,    # 8 分音符
        "dotted_8th": 3.0,  # 附點 8 分音符
        "quarter": 4.0,     # 4 分音符
        "dotted_quarter": 6.0,  # 附點 4 分音符
        "half": 8.0,    # 2 分音符
        "dotted_half": 12.0,  # 附點 2 分音符
        "whole": 16.0,  # 全音符
    }

    def __init__(self):
        self._chord_detector = ChordDetector()
        self._arranger = ArrangementPatterns()

    def split_hands(
        self, midi_data: "pretty_midi.PrettyMIDI", split_note: int = MIDDLE_C
    ) -> tuple[list["pretty_midi.Note"], list["pretty_midi.Note"]]:
        """根據音高分離左右手。"""
        treble_notes: list["pretty_midi.Note"] = []
        bass_notes: list["pretty_midi.Note"] = []

        for instrument in midi_data.instruments:
            for note in instrument.notes:
                if note.pitch >= split_note:
                    treble_notes = [*treble_notes, note]
                else:
                    bass_notes = [*bass_notes, note]

        return treble_notes, bass_notes

    def create_two_hand_midi(
        self,
        midi_data: "pretty_midi.PrettyMIDI",
        split_note: int = MIDDLE_C,
        pattern: PatternType = PatternType.ADAPTIVE,
        octave: int = DEFAULT_OCTAVE,
        velocity: int = DEFAULT_VELOCITY,
    ) -> "pretty_midi.PrettyMIDI":
        """建立雙手 MIDI，左手使用智慧編排。

        右手：原始高音區音符
        左手：根據和弦偵測結果 + 自適應伴奏型態產生
              （預設 ADAPTIVE 模式，參考 NicePianoSheet 風格）
        """
        import pretty_midi as pm

        tempo = self._estimate_tempo(midi_data)
        treble, _ = self.split_hands(midi_data, split_note)

        # 偵測和弦
        chords = self._chord_detector.detect_chords(
            midi_data, beats_per_measure=4, tempo=tempo,
        )

        # 產生左手伴奏（傳入右手音符供自適應分析）
        left_hand_events = self._arranger.generate(
            chords=chords,
            pattern=pattern,
            tempo=tempo,
            beats_per_measure=4,
            octave=octave,
            velocity=velocity,
            right_hand_notes=treble,
        )

        output = pm.PrettyMIDI(initial_tempo=tempo)

        # 右手
        right_hand = pm.Instrument(program=0, name="Right Hand")
        right_hand.notes = sorted(treble, key=lambda n: n.start)

        # 左手（從編排結果建立）
        left_hand = pm.Instrument(program=0, name="Left Hand")
        for event in left_hand_events:
            note = pm.Note(
                velocity=event.velocity,
                pitch=event.pitch,
                start=event.start,
                end=event.end,
            )
            left_hand.notes.append(note)
        left_hand.notes.sort(key=lambda n: n.start)

        output.instruments.append(right_hand)
        output.instruments.append(left_hand)

        return output

    def _estimate_tempo(self, midi_data: "pretty_midi.PrettyMIDI") -> float:
        tempo_changes = midi_data.get_tempo_changes()
        if len(tempo_changes[1]) > 0:
            return float(tempo_changes[1][0])
        return 120.0

    def quantize_midi(
        self,
        midi_data: "pretty_midi.PrettyMIDI",
        grid: str = "16th",
    ) -> "pretty_midi.PrettyMIDI":
        """量化 MIDI 音符到指定網格，改善節奏準確性
        
        使用統一的量化策略，避免多次量化導致的時值不一致問題。
        
        Args:
            midi_data: 輸入 MIDI
            grid: 量化網格 ("16th", "8th", "32nd")
        
        Returns:
            量化後的 MIDI
        """
        import pretty_midi as pm
        
        tempo = self._estimate_tempo(midi_data)
        quarter_duration = 60.0 / tempo
        
        # 設定量化網格大小
        grid_sizes = {
            "32nd": quarter_duration / 8,
            "16th": quarter_duration / 4,
            "8th": quarter_duration / 2,
            "quarter": quarter_duration,
        }
        grid_duration = grid_sizes.get(grid, quarter_duration / 4)
        
        output = pm.PrettyMIDI(initial_tempo=tempo)
        
        for instrument in midi_data.instruments:
            new_instrument = pm.Instrument(
                program=instrument.program,
                is_drum=instrument.is_drum,
                name=instrument.name
            )
            
            # 收集所有音符
            all_notes = instrument.notes.copy()
            if not all_notes:
                continue
            
            # 統一量化策略：先按音高分組，再量化
            notes_by_pitch = {}
            for note in all_notes:
                if note.pitch not in notes_by_pitch:
                    notes_by_pitch[note.pitch] = []
                notes_by_pitch[note.pitch].append(note)
            
            # 處理每個音高的音符
            for pitch, notes in notes_by_pitch.items():
                notes.sort(key=lambda n: n.start)
                
                quantized_notes = self._quantize_note_sequence(
                    notes, pitch, grid_duration, quarter_duration
                )
                new_instrument.notes.extend(quantized_notes)
            
            # 按開始時間排序
            new_instrument.notes.sort(key=lambda n: n.start)
            output.instruments.append(new_instrument)
        
        return output
    
    def _quantize_note_sequence(self, notes: list, pitch: int, grid_duration: float, quarter_duration: float) -> list:
        """量化一個音高的音符序列，保持時值正確"""
        import pretty_midi as pm
        
        if not notes:
            return []
        
        result = []
        i = 0
        min_note_duration = grid_duration * 0.5  # 最小允許 50% 網格
        
        while i < len(notes):
            current = notes[i]
            
            # 量化開始和結束時間
            quantized_start = round(current.start / grid_duration) * grid_duration
            quantized_end = round(current.end / grid_duration) * grid_duration
            
            # 確保最小長度
            if quantized_end <= quantized_start:
                quantized_end = quantized_start + grid_duration
            
            # 嘗試合併後續相近的音符
            merge_end = quantized_end
            j = i + 1
            merge_threshold = quarter_duration  # 1 拍的合併閾值
            
            while j < len(notes):
                next_note = notes[j]
                gap = next_note.start - notes[j-1].end
                
                if gap < merge_threshold and next_note.pitch == pitch:
                    # 延長合併結束時間
                    next_quantized_end = round(next_note.end / grid_duration) * grid_duration
                    if next_quantized_end > merge_end:
                        merge_end = next_quantized_end
                    j += 1
                else:
                    break
            
            # 確保合併後的長度合理
            final_duration = merge_end - quantized_start
            if final_duration < min_note_duration:
                final_duration = min_note_duration
            
            # 向上取整到標準時值
            final_duration = self._round_to_standard_duration(
                final_duration, quarter_duration
            )
            final_end = quantized_start + final_duration
            
            new_note = pm.Note(
                velocity=current.velocity,
                pitch=pitch,
                start=quantized_start,
                end=final_end
            )
            result.append(new_note)
            
            i = j
        
        return result
    
    def _round_to_standard_duration(self, duration: float, quarter_duration: float) -> float:
        """將時值四捨五入到最接近的標準時值"""
        # 以 16 分音符為單位計算
        sixteenths = duration / quarter_duration * 4
        
        # 標準時值（以 16 分音符為單位）
        standards = [16, 12, 8, 6, 4, 3, 2, 1, 0.5]
        
        # 找最接近的
        closest = min(standards, key=lambda s: abs(s - sixteenths))
        
        return closest * quarter_duration / 4
