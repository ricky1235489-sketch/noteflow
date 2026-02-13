"""MIDI → LilyPond → PDF 樂譜產生器

使用 LilyPond 產生專業品質的鋼琴樂譜。
"""
from __future__ import annotations

import logging
import subprocess
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)


# LilyPond 路徑 - 自動偵測 Windows 或 Linux
import shutil
import platform

def _get_lilypond_path() -> str:
    # 先嘗試系統 PATH 中的 lilypond
    lilypond_in_path = shutil.which("lilypond")
    if lilypond_in_path:
        return lilypond_in_path
    
    # Windows 路徑
    if platform.system() == "Windows":
        return r"C:\Users\tianq\OneDrive\Desktop\project3\lilypond-2.24.4\bin\lilypond.exe"
    
    # Linux/WSL 預設
    return "/usr/bin/lilypond"

LILYPOND_PATH = _get_lilypond_path()


class SheetGenerator:
    """MIDI → MusicXML / LilyPond → PDF 樂譜產生器"""

    def midi_to_musicxml(self, midi_path: str, output_path: str, title: str = "Piano Score") -> str:
        """將 MIDI 轉為高品質 MusicXML（類似 PopPianoAI 輸出格式）
        
        產生雙譜表鋼琴譜，包含：
        - 正確的調號、拍號、速度標記
        - 右手（高音譜號）和左手（低音譜號）分離
        - 適當的音符時值（不只是 16 分音符）
        - 和弦標記
        """
        import pretty_midi as pm
        import xml.etree.ElementTree as ET
        from datetime import date
        
        midi = pm.PrettyMIDI(midi_path)
        
        # 取得 tempo
        tempo_changes = midi.get_tempo_changes()
        bpm = int(tempo_changes[1][0]) if len(tempo_changes[1]) > 0 else 120
        
        # 偵測調性
        key_note, key_mode = self._detect_key(midi)
        fifths = self._key_to_fifths(key_note, key_mode)
        
        # MusicXML divisions (每四分音符的 tick 數)
        divisions = 10080
        
        # 分離左右手音符
        right_hand_notes = []
        left_hand_notes = []
        
        for inst in midi.instruments:
            for n in inst.notes:
                if n.pitch >= 60:  # Middle C 以上 = 右手
                    right_hand_notes.append(n)
                else:
                    left_hand_notes.append(n)
        
        # 量化參數
        quarter_duration = 60.0 / bpm
        measure_duration = 4 * quarter_duration  # 4/4 拍
        
        # 計算總小節數
        total_duration = midi.get_end_time()
        num_measures = max(1, int(total_duration / measure_duration) + 1)
        
        # 量化音符到時間槽
        rh_events = self._quantize_notes_for_xml(right_hand_notes, bpm, divisions)
        lh_events = self._quantize_notes_for_xml(left_hand_notes, bpm, divisions)
        
        # 建立 MusicXML
        root = ET.Element('score-partwise', version='4.0')
        
        # movement-title
        movement_title = ET.SubElement(root, 'movement-title')
        movement_title.text = title
        
        # identification
        identification = ET.SubElement(root, 'identification')
        creator = ET.SubElement(identification, 'creator', type='composer')
        rights = ET.SubElement(identification, 'rights')
        rights.text = 'Crafted with NoteFlow'
        encoding = ET.SubElement(identification, 'encoding')
        encoding_date = ET.SubElement(encoding, 'encoding-date')
        encoding_date.text = date.today().isoformat()
        software = ET.SubElement(encoding, 'software')
        software.text = 'NoteFlow Piano Transcription'
        
        # defaults (頁面設定)
        defaults = ET.SubElement(root, 'defaults')
        scaling = ET.SubElement(defaults, 'scaling')
        ET.SubElement(scaling, 'millimeters').text = '7.05556'
        ET.SubElement(scaling, 'tenths').text = '40'
        
        page_layout = ET.SubElement(defaults, 'page-layout')
        ET.SubElement(page_layout, 'page-height').text = '1683.78'
        ET.SubElement(page_layout, 'page-width').text = '1190.55'
        page_margins = ET.SubElement(page_layout, 'page-margins')
        ET.SubElement(page_margins, 'left-margin').text = '56.6929'
        ET.SubElement(page_margins, 'right-margin').text = '56.6929'
        ET.SubElement(page_margins, 'top-margin').text = '56.6929'
        ET.SubElement(page_margins, 'bottom-margin').text = '113.386'
        
        # part-list
        part_list = ET.SubElement(root, 'part-list')
        score_part = ET.SubElement(part_list, 'score-part', id='P1')
        ET.SubElement(score_part, 'part-name')
        score_inst = ET.SubElement(score_part, 'score-instrument', id='I1')
        ET.SubElement(score_inst, 'instrument-name').text = 'Piano'
        ET.SubElement(score_inst, 'instrument-abbreviation').text = 'Pno'
        midi_inst = ET.SubElement(score_part, 'midi-instrument', id='I1')
        ET.SubElement(midi_inst, 'midi-channel').text = '1'
        ET.SubElement(midi_inst, 'midi-program').text = '1'
        
        # part
        part = ET.SubElement(root, 'part', id='P1')
        
        ticks_per_measure = divisions * 4  # 4/4 拍
        
        for measure_num in range(num_measures):
            measure = ET.SubElement(part, 'measure', number=str(measure_num + 1))
            
            measure_start_tick = measure_num * ticks_per_measure
            measure_end_tick = measure_start_tick + ticks_per_measure
            
            # 第一小節加入屬性
            if measure_num == 0:
                attributes = ET.SubElement(measure, 'attributes')
                ET.SubElement(attributes, 'divisions').text = str(divisions)
                
                key_elem = ET.SubElement(attributes, 'key')
                ET.SubElement(key_elem, 'fifths').text = str(fifths)
                
                time_elem = ET.SubElement(attributes, 'time')
                ET.SubElement(time_elem, 'beats').text = '4'
                ET.SubElement(time_elem, 'beat-type').text = '4'
                
                ET.SubElement(attributes, 'staves').text = '2'
                
                clef1 = ET.SubElement(attributes, 'clef', number='1')
                ET.SubElement(clef1, 'sign').text = 'G'
                ET.SubElement(clef1, 'line').text = '2'
                
                clef2 = ET.SubElement(attributes, 'clef', number='2')
                ET.SubElement(clef2, 'sign').text = 'F'
                ET.SubElement(clef2, 'line').text = '4'
                
                # 速度標記
                direction = ET.SubElement(measure, 'direction', placement='above')
                direction_type = ET.SubElement(direction, 'direction-type')
                metronome = ET.SubElement(direction_type, 'metronome')
                ET.SubElement(metronome, 'beat-unit').text = 'quarter'
                ET.SubElement(metronome, 'per-minute').text = str(bpm)
                ET.SubElement(direction, 'staff').text = '1'
                sound = ET.SubElement(direction, 'sound', tempo=str(bpm))
            
            # 取得這個小節的音符
            rh_measure_events = [e for e in rh_events 
                                 if measure_start_tick <= e['start_tick'] < measure_end_tick]
            lh_measure_events = [e for e in lh_events 
                                 if measure_start_tick <= e['start_tick'] < measure_end_tick]
            
            # 寫入右手 (voice 1, staff 1)
            # _write_voice_to_measure 會用休止符填滿整個小節，
            # 所以 backup 的 duration 總是 ticks_per_measure
            self._write_voice_to_measure(measure, rh_measure_events, measure_start_tick, 
                                         ticks_per_measure, divisions, voice='1', staff='1',
                                         key_fifths=fifths)
            
            # backup 到小節開頭（右手聲部總是填滿整個小節）
            backup = ET.SubElement(measure, 'backup')
            ET.SubElement(backup, 'duration').text = str(ticks_per_measure)
            
            # 寫入左手 (voice 2, staff 2)
            self._write_voice_to_measure(measure, lh_measure_events, measure_start_tick,
                                         ticks_per_measure, divisions, voice='2', staff='2',
                                         key_fifths=fifths)
        
        # 寫入檔案
        tree = ET.ElementTree(root)
        ET.indent(tree, space='  ')
        
        # 加入 XML 宣告和 DOCTYPE
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n')
            f.write('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" '
                    '"http://www.musicxml.org/dtds/partwise.dtd">\n')
            tree.write(f, encoding='unicode', xml_declaration=False)
        
        return output_path
    
    def _key_to_fifths(self, key_note: str, key_mode: str) -> int:
        """將調名轉換為五度圈位置"""
        # 大調的五度圈位置
        major_fifths = {
            'c': 0, 'g': 1, 'd': 2, 'a': 3, 'e': 4, 'b': 5, 'fis': 6,
            'f': -1, 'bes': -2, 'ees': -3, 'aes': -4, 'des': -5, 'ges': -6,
        }
        return major_fifths.get(key_note, 0)
    
    def _merge_consecutive_notes(self, notes: list, eighth_duration: float) -> list:
        """合併連續的同音音符，並將時值向上取整到標準音符
        
        如果兩個相同音高的音符間隔很小，合併成一個較長的音符。
        合併後的時值會向上取整到最接近的標準音符時值（只允許單一附點）。
        這可以清理 Pop2Piano 產生的重複音符，讓樂譜更乾淨。
        """
        if not notes:
            return notes
        
        # 按音高分組
        from collections import defaultdict
        by_pitch = defaultdict(list)
        for n in notes:
            by_pitch[n.pitch].append(n)
        
        merged = []
        
        # 合併閾值：四分音符範圍內的同音合併
        merge_threshold = eighth_duration * 2  # = quarter note duration
        
        # 標準音符時值（以八分音符為單位）
        # 只允許：16分(0.5)、8分(1)、附點8分(1.5)、4分(2)、附點4分(3)、2分(4)、附點2分(6)、全音符(8)
        standard_durations_in_eighths = [8, 6, 4, 3, 2, 1.5, 1, 0.5]
        
        for pitch, pitch_notes in by_pitch.items():
            # 按開始時間排序
            pitch_notes.sort(key=lambda n: n.start)
            
            i = 0
            while i < len(pitch_notes):
                current = pitch_notes[i]
                merged_start = current.start
                merged_end = current.end
                max_velocity = current.velocity
                
                # 嘗試合併後續的同音音符
                j = i + 1
                while j < len(pitch_notes):
                    next_note = pitch_notes[j]
                    gap = next_note.start - merged_end
                    
                    # 如果間隔小於閾值，或者下一個音符開始於當前音符結束之前（重疊），合併
                    if gap < merge_threshold or next_note.start <= merged_end:
                        merged_end = max(merged_end, next_note.end)
                        max_velocity = max(max_velocity, next_note.velocity)
                        j += 1
                    else:
                        break
                
                # 計算合併後的時值（以八分音符為單位）
                duration_in_eighths = (merged_end - merged_start) / eighth_duration
                
                # 向上取整到最接近的標準時值
                rounded_duration_eighths = min(
                    (d for d in standard_durations_in_eighths if d >= duration_in_eighths),
                    default=standard_durations_in_eighths[0]  # 最大值
                )
                
                # 轉換回秒
                final_end = merged_start + (rounded_duration_eighths * eighth_duration)
                
                # 建立合併後的音符
                class MergedNote:
                    def __init__(self, pitch, start, end, velocity):
                        self.pitch = pitch
                        self.start = start
                        self.end = end
                        self.velocity = velocity
                
                merged.append(MergedNote(
                    pitch=pitch,
                    start=merged_start,
                    end=final_end,
                    velocity=max_velocity
                ))
                
                i = j
        
        # 按開始時間排序
        merged.sort(key=lambda n: (n.start, n.pitch))
        
        logger.info(f"Merged {len(notes)} notes into {len(merged)} notes (rounded to standard durations)")
        return merged
    
    def _quantize_notes_for_xml(self, notes: list, bpm: int, divisions: int) -> list:
        """將音符量化為 MusicXML 事件（嚴格量化到 16 分音符網格）
        
        使用 16 分音符作為最小單位，嚴格對齊到節奏網格。
        這會產生更乾淨、更易演奏的樂譜。
        """
        quarter_duration = 60.0 / bpm
        sixteenth_duration = quarter_duration / 4  # 16 分音符時長
        ticks_per_sixteenth = divisions // 4  # 2520
        ticks_per_measure = divisions * 4  # 40320
        
        # 先過濾掉太短的音符（可能是雜訊）
        min_duration = sixteenth_duration * 0.75  # 至少 3/4 個 16 分音符
        notes = [n for n in notes if (n.end - n.start) >= min_duration]
        
        # 合併相近的同音音符（八分音符範圍內）
        eighth_duration = quarter_duration / 2
        notes = self._merge_consecutive_notes(notes, eighth_duration)
        
        events = []
        for n in notes:
            # 嚴格量化到 16 分音符網格
            start_sixteenth = round(n.start / sixteenth_duration)
            end_sixteenth = round(n.end / sixteenth_duration)
            
            # 確保至少有 1 個 16 分音符的長度
            if end_sixteenth <= start_sixteenth:
                end_sixteenth = start_sixteenth + 1
            
            start_tick = start_sixteenth * ticks_per_sixteenth
            duration_sixteenths = end_sixteenth - start_sixteenth
            duration_ticks = duration_sixteenths * ticks_per_sixteenth
            
            # 量化到標準時值（16分、8分、4分、附點等）
            duration_ticks = self._quantize_duration(duration_ticks, divisions)
            
            # 檢查是否跨小節，需要 tie
            measure_start = (start_tick // ticks_per_measure) * ticks_per_measure
            measure_end = measure_start + ticks_per_measure
            end_tick = start_tick + duration_ticks
            
            if end_tick > measure_end:
                # 跨小節：分割成多個 tied 音符
                first_duration = measure_end - start_tick
                remaining = end_tick - measure_end
                
                # 第一個音符 (tie start)
                events.append({
                    'pitch': n.pitch,
                    'velocity': n.velocity,
                    'start_tick': start_tick,
                    'duration_ticks': self._quantize_duration(first_duration, divisions),
                    'tie_start': True,
                    'tie_stop': False,
                })
                
                # 後續音符 (可能還要繼續分割)
                current_tick = measure_end
                while remaining > 0:
                    next_measure_end = current_tick + ticks_per_measure
                    chunk = min(remaining, ticks_per_measure)
                    is_last = (remaining <= ticks_per_measure)
                    
                    events.append({
                        'pitch': n.pitch,
                        'velocity': n.velocity,
                        'start_tick': current_tick,
                        'duration_ticks': self._quantize_duration(chunk, divisions),
                        'tie_start': not is_last,
                        'tie_stop': True,
                    })
                    
                    remaining -= chunk
                    current_tick = next_measure_end
            else:
                # 不跨小節
                events.append({
                    'pitch': n.pitch,
                    'velocity': n.velocity,
                    'start_tick': start_tick,
                    'duration_ticks': duration_ticks,
                    'tie_start': False,
                    'tie_stop': False,
                })
        
        # 按開始時間排序
        events.sort(key=lambda e: (e['start_tick'], e['pitch']))
        logger.info(f"Quantized {len(notes)} notes to {len(events)} events (strict 16th note grid)")
        return events
    
    def _quantize_duration(self, ticks: int, divisions: int) -> int:
        """將時值量化到最接近的標準音符時值（PopPianoAI 風格）
        
        PopPianoAI 使用的時值（divisions=10080）：
        - 2520: 16分音符
        - 5040: 8分音符  
        - 7560: 附點8分音符
        - 10080: 4分音符
        - 15120: 附點4分音符
        - 20160: 2分音符
        - 30240: 附點2分音符
        - 40320: 全音符
        """
        # 標準時值（以 divisions=10080 為四分音符）
        standard_durations = [
            divisions * 4,          # 40320 全音符
            divisions * 3,          # 30240 附點二分音符
            divisions * 2,          # 20160 二分音符
            divisions * 3 // 2,     # 15120 附點四分音符
            divisions,              # 10080 四分音符
            divisions * 3 // 4,     # 7560 附點八分音符
            divisions // 2,         # 5040 八分音符
            divisions // 4,         # 2520 16 分音符
        ]
        
        # 找最接近的標準時值
        closest = min(standard_durations, key=lambda d: abs(d - ticks))
        return closest
    
    def _write_voice_to_measure(self, measure, events: list, measure_start_tick: int,
                                ticks_per_measure: int, divisions: int, voice: str, staff: str,
                                key_fifths: int = 0):
        """將一個聲部的音符寫入小節（嚴格 4/4 拍）
        
        確保每個小節的音符時值總和 = ticks_per_measure
        """
        import xml.etree.ElementTree as ET
        
        if not events:
            # 空聲部，寫入全休止符
            note_elem = ET.SubElement(measure, 'note')
            ET.SubElement(note_elem, 'rest')
            ET.SubElement(note_elem, 'duration').text = str(ticks_per_measure)
            ET.SubElement(note_elem, 'voice').text = voice
            ET.SubElement(note_elem, 'type').text = 'whole'
            ET.SubElement(note_elem, 'staff').text = staff
            return
        
        current_tick = measure_start_tick
        measure_end_tick = measure_start_tick + ticks_per_measure
        eighth_duration = divisions // 2  # 5040
        
        # 按時間分組（同時開始的音符形成和弦）
        time_groups: dict[int, list] = {}
        for e in events:
            rel_tick = e['start_tick'] - measure_start_tick
            if 0 <= rel_tick < ticks_per_measure:  # 只處理在小節內的音符
                if rel_tick not in time_groups:
                    time_groups[rel_tick] = []
                time_groups[rel_tick].append(e)
        
        sorted_times = sorted(time_groups.keys())
        
        # 追蹤 beam 狀態
        beam_notes = []  # 收集需要 beam 的八分音符
        total_duration_written = 0  # 追蹤已寫入的時值
        
        for i, rel_tick in enumerate(sorted_times):
            abs_tick = measure_start_tick + rel_tick
            
            # 如果有間隙，加入休止符
            if abs_tick > current_tick:
                gap = abs_tick - current_tick
                # 確保休止符不超出小節
                gap = min(gap, measure_end_tick - current_tick)
                if gap > 0:
                    self._write_rest(measure, gap, divisions, voice, staff)
                    total_duration_written += gap
                    beam_notes = []  # 休止符打斷 beam
            
            group = time_groups[rel_tick]
            duration = group[0]['duration_ticks']
            
            # 嚴格限制在小節內 - 不能超出
            remaining_in_measure = measure_end_tick - abs_tick
            duration = min(duration, remaining_in_measure)
            
            # 如果時值會導致超出小節，截斷它
            if total_duration_written + duration > ticks_per_measure:
                duration = ticks_per_measure - total_duration_written
            
            if duration <= 0:
                break  # 小節已滿
            
            # 判斷是否為八分音符或16分音符（可以 beam）
            is_eighth = (duration == eighth_duration)
            is_sixteenth = (duration == divisions // 4)  # 2520
            
            # 寫入音符或和弦
            for j, event in enumerate(sorted(group, key=lambda e: e['pitch'])):
                note_elem = ET.SubElement(measure, 'note')
                
                # 動態（velocity）- PopPianoAI 風格
                velocity_pct = event['velocity'] / 127 * 100
                note_elem.set('dynamics', f"{velocity_pct:.2f}")
                
                if j > 0:
                    ET.SubElement(note_elem, 'chord')
                
                pitch_elem = ET.SubElement(note_elem, 'pitch')
                step, alter, octave = self._midi_to_pitch(event['pitch'], key_fifths)
                ET.SubElement(pitch_elem, 'step').text = step
                if alter != 0:
                    ET.SubElement(pitch_elem, 'alter').text = str(alter)
                ET.SubElement(pitch_elem, 'octave').text = str(octave)
                
                ET.SubElement(note_elem, 'duration').text = str(duration)
                
                # Tie 處理 - PopPianoAI 風格
                if event.get('tie_start'):
                    ET.SubElement(note_elem, 'tie', type='start')
                if event.get('tie_stop'):
                    ET.SubElement(note_elem, 'tie', type='stop')
                
                ET.SubElement(note_elem, 'voice').text = voice
                
                note_type = self._duration_to_type(duration, divisions)
                ET.SubElement(note_elem, 'type').text = note_type
                
                # 附點 - 只允許單一附點
                if self._is_dotted(duration, divisions):
                    ET.SubElement(note_elem, 'dot')
                
                # stem 方向
                stem = ET.SubElement(note_elem, 'stem')
                stem.text = 'up' if staff == '1' else 'down'
                
                ET.SubElement(note_elem, 'staff').text = staff
                
                # Notations (tied) - PopPianoAI 風格
                if event.get('tie_start') or event.get('tie_stop'):
                    notations = ET.SubElement(note_elem, 'notations')
                    if event.get('tie_start'):
                        ET.SubElement(notations, 'tied', type='start')
                    if event.get('tie_stop'):
                        ET.SubElement(notations, 'tied', type='stop')
                
                # Beam 處理（只對第一個音符，和弦音符不加 beam）
                if j == 0 and (is_eighth or is_sixteenth):
                    beam_notes.append((note_elem, is_sixteenth))
            
            current_tick = abs_tick + duration
            total_duration_written += duration
            
            # 如果小節已滿，停止
            if total_duration_written >= ticks_per_measure:
                break
        
        # 處理 beam（每 2-4 個八分音符一組）
        self._apply_beams(beam_notes)
        
        # 小節結尾的休止符 - 確保總時值 = ticks_per_measure
        if total_duration_written < ticks_per_measure:
            gap = ticks_per_measure - total_duration_written
            self._write_rest(measure, gap, divisions, voice, staff)
    
    def _apply_beams(self, beam_notes: list):
        """對八分音符和16分音符應用 beam（PopPianoAI 風格：按拍分組）
        
        beam_notes: list of (note_elem, is_sixteenth) tuples
        """
        import xml.etree.ElementTree as ET
        
        if len(beam_notes) < 2:
            return
        
        # PopPianoAI 風格：每 2 個八分音符一組（一拍）
        # 但最多連續 4 個（兩拍）
        i = 0
        while i < len(beam_notes):
            # 找出這一組的結束位置（最多 4 個，或遇到休止符/和弦打斷）
            group_end = min(i + 4, len(beam_notes))
            group_size = group_end - i
            
            if group_size >= 2:
                for j in range(group_size):
                    note_elem, is_sixteenth = beam_notes[i + j]
                    
                    # beam number="1" 用於八分音符層級
                    beam1 = ET.SubElement(note_elem, 'beam', number='1')
                    if j == 0:
                        beam1.text = 'begin'
                    elif j == group_size - 1:
                        beam1.text = 'end'
                    else:
                        beam1.text = 'continue'
                    
                    # beam number="2" 用於16分音符層級
                    if is_sixteenth:
                        beam2 = ET.SubElement(note_elem, 'beam', number='2')
                        # 檢查前後是否也是16分音符
                        prev_is_16th = (j > 0 and beam_notes[i + j - 1][1])
                        next_is_16th = (j < group_size - 1 and beam_notes[i + j + 1][1])
                        
                        if not prev_is_16th and next_is_16th:
                            beam2.text = 'begin'
                        elif prev_is_16th and not next_is_16th:
                            beam2.text = 'end'
                        elif prev_is_16th and next_is_16th:
                            beam2.text = 'continue'
                        else:
                            # 單獨的16分音符，用 hook
                            beam2.text = 'forward hook' if j < group_size - 1 else 'backward hook'
            
            i = group_end
    
    def _write_rest(self, measure, duration: int, divisions: int, voice: str, staff: str):
        """寫入休止符"""
        import xml.etree.ElementTree as ET
        
        note_elem = ET.SubElement(measure, 'note')
        ET.SubElement(note_elem, 'rest')
        ET.SubElement(note_elem, 'duration').text = str(duration)
        ET.SubElement(note_elem, 'voice').text = voice
        note_type = self._duration_to_type(duration, divisions)
        ET.SubElement(note_elem, 'type').text = note_type
        if self._is_dotted(duration, divisions):
            ET.SubElement(note_elem, 'dot')
        ET.SubElement(note_elem, 'staff').text = staff
    
    def _midi_to_pitch(self, midi_pitch: int, key_fifths: int = 0) -> tuple[str, int, int]:
        """將 MIDI 音高轉換為 (step, alter, octave)
        
        PopPianoAI 風格：根據調號決定升降記號
        """
        # 調號中的升降音
        sharp_keys = {1: {6}, 2: {6, 1}, 3: {6, 1, 8}, 4: {6, 1, 8, 3}, 
                      5: {6, 1, 8, 3, 10}, 6: {6, 1, 8, 3, 10, 5}}
        flat_keys = {-1: {10}, -2: {10, 3}, -3: {10, 3, 8}, -4: {10, 3, 8, 1},
                     -5: {10, 3, 8, 1, 6}, -6: {10, 3, 8, 1, 6, 11}}
        
        pc = midi_pitch % 12
        octave = (midi_pitch // 12) - 1
        
        # 基本音名對應（使用升號）
        pitch_map_sharp = [
            ('C', 0), ('C', 1), ('D', 0), ('D', 1), ('E', 0), ('F', 0),
            ('F', 1), ('G', 0), ('G', 1), ('A', 0), ('A', 1), ('B', 0)
        ]
        # 使用降號的對應
        pitch_map_flat = [
            ('C', 0), ('D', -1), ('D', 0), ('E', -1), ('E', 0), ('F', 0),
            ('G', -1), ('G', 0), ('A', -1), ('A', 0), ('B', -1), ('B', 0)
        ]
        
        # 根據調號選擇升降
        if key_fifths > 0:
            step, alter = pitch_map_sharp[pc]
        elif key_fifths < 0:
            step, alter = pitch_map_flat[pc]
        else:
            step, alter = pitch_map_sharp[pc]
        
        return step, alter, octave
    
    def _duration_to_type(self, duration: int, divisions: int) -> str:
        """將 tick 時值轉換為音符類型名稱"""
        # 移除附點部分來判斷基本時值
        base_duration = duration
        if self._is_dotted(duration, divisions):
            base_duration = duration * 2 // 3
        
        ratio = base_duration / divisions
        
        if ratio >= 4:
            return 'whole'
        elif ratio >= 2:
            return 'half'
        elif ratio >= 1:
            return 'quarter'
        elif ratio >= 0.5:
            return 'eighth'
        elif ratio >= 0.25:
            return '16th'
        else:
            return '32nd'
    
    def _is_dotted(self, duration: int, divisions: int) -> bool:
        """判斷是否為附點音符"""
        dotted_durations = [
            divisions * 3,          # 30240 附點二分音符
            divisions * 3 // 2,     # 15120 附點四分音符
            divisions * 3 // 4,     # 7560 附點八分音符
        ]
        return duration in dotted_durations

    def midi_to_pdf(self, midi_path: str, output_path: str, title: str = "Piano Score") -> str:
        """將 MIDI 轉為專業品質 PDF（使用 MusicXML → MuseScore）
        
        流程：
        1. 先生成 MusicXML（經過量化和清理）
        2. 使用 MuseScore 將 MusicXML 轉為 PDF
        
        這樣 PDF 和螢幕顯示的樂譜會完全一致。
        """
        # 1. 生成 MusicXML
        xml_path = output_path.replace(".pdf", ".musicxml")
        self.midi_to_musicxml(midi_path, xml_path, title)
        
        # 2. 使用 MuseScore 轉換 MusicXML → PDF
        try:
            return self._musescore_render(xml_path, output_path)
        except Exception as e:
            logger.warning(f"MuseScore conversion failed: {e}")
            logger.warning("PDF will not be available, but MusicXML is ready for display")
            # Return the XML path as fallback
            return xml_path
    
    def _musescore_render(self, musicxml_path: str, output_path: str) -> str:
        """使用 MuseScore 將 MusicXML 轉為 PDF"""
        import shutil
        
        # 尋找 MuseScore 執行檔
        musescore_paths = [
            "musescore",  # Linux/Mac (in PATH)
            "/usr/bin/musescore",  # Linux
            "/usr/local/bin/musescore",  # Linux/Mac
            "C:\\Program Files\\MuseScore 4\\bin\\MuseScore4.exe",  # Windows MuseScore 4
            "C:\\Program Files\\MuseScore 3\\bin\\MuseScore3.exe",  # Windows MuseScore 3
            "/mnt/c/Program Files/MuseScore 4/bin/MuseScore4.exe",  # WSL → Windows MuseScore 4
            "/mnt/c/Program Files/MuseScore 3/bin/MuseScore3.exe",  # WSL → Windows MuseScore 3
        ]
        
        musescore_cmd = None
        for path in musescore_paths:
            if shutil.which(path) or Path(path).exists():
                musescore_cmd = path
                break
        
        if musescore_cmd is None:
            raise RuntimeError(
                "MuseScore not found. Please install MuseScore:\n"
                "  Linux: sudo apt install musescore3\n"
                "  Mac: brew install musescore\n"
                "  Windows: Download from https://musescore.org"
            )
        
        # 執行 MuseScore 轉換
        # -o: output file
        # --force: overwrite existing file
        result = subprocess.run(
            [musescore_cmd, musicxml_path, "-o", output_path],
            capture_output=True,
            text=True,
            timeout=60,
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"MuseScore conversion error: {result.stderr}")
        
        if not Path(output_path).exists():
            raise RuntimeError("MuseScore did not produce PDF")
        
        logger.info(f"PDF generated via MuseScore: {output_path}")
        return output_path

    def _lilypond_render(self, midi_path: str, output_path: str, title: str) -> str:
        """使用 LilyPond 渲染 MIDI 為 PDF"""
        import pretty_midi as pm

        midi = pm.PrettyMIDI(midi_path)
        ly_content = self._midi_to_lilypond(midi, title)

        # 寫入 .ly 檔案
        output_dir = Path(output_path).parent
        ly_path = output_dir / "score.ly"
        ly_path.write_text(ly_content, encoding="utf-8")

        # 執行 LilyPond
        result = subprocess.run(
            [LILYPOND_PATH, "-o", str(output_dir / "score"), str(ly_path)],
            capture_output=True,
            text=True,
            timeout=120,
        )

        if result.returncode != 0:
            raise RuntimeError(f"LilyPond error: {result.stderr}")

        # LilyPond 輸出 score.pdf
        generated_pdf = output_dir / "score.pdf"
        if generated_pdf.exists():
            generated_pdf.rename(output_path)
            return output_path

        raise RuntimeError("LilyPond did not produce PDF")

    def _detect_key(self, midi) -> tuple[str, str]:
        """偵測調性，回傳 (音名, 大小調)"""
        from collections import Counter
        
        # 收集所有音符的 pitch class
        pitch_classes = []
        for inst in midi.instruments:
            for note in inst.notes:
                pitch_classes.append(note.pitch % 12)
        
        if not pitch_classes:
            return ("c", "major")
        
        counts = Counter(pitch_classes)
        
        # 大調音階模板 (相對於主音的半音數)
        major_template = {0, 2, 4, 5, 7, 9, 11}
        
        # 測試每個可能的主音
        best_key = 0
        best_score = 0
        
        for root in range(12):
            # 將模板移調到這個主音
            scale = {(root + interval) % 12 for interval in major_template}
            # 計算符合的音符數
            score = sum(counts[pc] for pc in scale)
            if score > best_score:
                best_score = score
                best_key = root
        
        # MIDI pitch class 到 LilyPond 調名
        key_names = ["c", "des", "d", "ees", "e", "f", "fis", "g", "aes", "a", "bes", "b"]
        
        return (key_names[best_key], "major")

    def _midi_to_lilypond(self, midi: "pm.PrettyMIDI", title: str) -> str:
        """將 MIDI 轉換為 LilyPond 格式"""
        # 取得 tempo
        tempo_changes = midi.get_tempo_changes()
        tempo = int(tempo_changes[1][0]) if len(tempo_changes[1]) > 0 else 120

        # 偵測調性
        key_note, key_mode = self._detect_key(midi)

        # 分離左右手
        right_hand_notes = []
        left_hand_notes = []

        for inst in midi.instruments:
            for note in inst.notes:
                if note.pitch >= 60:  # Middle C 以上 = 右手
                    right_hand_notes.append(note)
                else:
                    left_hand_notes.append(note)

        # 產生 LilyPond 程式碼
        ly = f'''\\version "2.24.0"

\\header {{
  title = "{title}"
  tagline = ##f
}}

\\paper {{
  #(set-paper-size "a4")
  top-margin = 15\\mm
  bottom-margin = 15\\mm
  left-margin = 15\\mm
  right-margin = 15\\mm
}}

global = {{
  \\key {key_note} \\{key_mode}
  \\time 4/4
  \\tempo 4 = {tempo}
}}

right = {{
  \\global
  \\clef treble
  {self._notes_to_lilypond(right_hand_notes, midi.get_end_time(), tempo)}
}}

left = {{
  \\global
  \\clef bass
  {self._notes_to_lilypond(left_hand_notes, midi.get_end_time(), tempo)}
}}

\\score {{
  \\new PianoStaff \\with {{
    instrumentName = "Piano"
  }} <<
    \\new Staff = "right" \\right
    \\new Staff = "left" \\left
  >>
  \\layout {{ }}
  \\midi {{ }}
}}
'''
        return ly

    def _notes_to_lilypond(self, notes: list, total_duration: float, tempo: int = 120) -> str:
        """將音符列表轉換為 LilyPond 音符字串"""
        if not notes:
            # 空的話產生休止符
            measures = max(1, int(total_duration / 2))
            return "R1*" + str(measures)

        # 按時間排序
        notes = sorted(notes, key=lambda n: n.start)

        # 量化到 16 分音符
        sixteenth_duration = 60.0 / tempo / 4
        
        # 收集每個時間點的音符
        time_slots: dict[int, list[int]] = {}
        for note in notes:
            slot = int(note.start / sixteenth_duration)
            if slot not in time_slots:
                time_slots[slot] = []
            time_slots[slot].append(note.pitch)

        # 產生 LilyPond 字串
        ly_notes = []
        current_slot = 0
        max_slot = max(time_slots.keys()) if time_slots else 0

        while current_slot <= max_slot:
            if current_slot in time_slots:
                pitches = time_slots[current_slot]
                if len(pitches) == 1:
                    ly_notes.append(self._pitch_to_lily(pitches[0]) + "16")
                else:
                    # 和弦
                    chord = "<" + " ".join(self._pitch_to_lily(p) for p in sorted(pitches)) + ">16"
                    ly_notes.append(chord)
            else:
                ly_notes.append("r16")
            current_slot += 1

        # 每 16 個音符換行（一小節 4/4）
        lines = []
        for i in range(0, len(ly_notes), 16):
            lines.append(" ".join(ly_notes[i:i+16]))

        return "\n  ".join(lines) if lines else "R1"

    def _pitch_to_lily(self, midi_pitch: int) -> str:
        """將 MIDI 音高轉換為 LilyPond 音符名稱"""
        note_names = ["c", "cis", "d", "dis", "e", "f", "fis", "g", "gis", "a", "ais", "b"]
        octave = (midi_pitch // 12) - 1
        note = note_names[midi_pitch % 12]

        # LilyPond 八度標記：c' = C4, c'' = C5, c = C3, c, = C2
        if octave == 4:
            return note + "'"
        elif octave == 5:
            return note + "''"
        elif octave == 6:
            return note + "'''"
        elif octave == 3:
            return note
        elif octave == 2:
            return note + ","
        elif octave == 1:
            return note + ",,"
        else:
            return note + "'" * max(0, octave - 4) if octave > 4 else note + "," * max(0, 3 - octave)
