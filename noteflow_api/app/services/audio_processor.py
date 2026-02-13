from __future__ import annotations

import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import pretty_midi

logger = logging.getLogger(__name__)


class AudioProcessor:
    """音訊轉鋼琴譜處理器

    支援多種轉錄模式：
    1. Pop2Piano - 將流行音樂轉換為鋼琴編曲（適合非鋼琴音源）
    2. ByteDance Piano Transcription - 高精度鋼琴轉錄（適合鋼琴錄音）
    3. Basic Pitch - 通用音高檢測（fallback）
    
    支援載入微調後的 Pop2Piano 模型以提升品質。
    
    Pop2Piano Composer Styles:
    - composer2: Simple & Clean (簡單清晰)
    - composer4: Balanced (平衡推薦) ⭐
    - composer7: Rich & Complex (豐富複雜)
    - composer10: Moderate (中等難度)
    - composer15: Full Arrangement (完整編曲)
    - composer20: Advanced (進階)
    """

    def __init__(self, model_path: str = None, progress_callback=None):
        """初始化音訊處理器

        Args:
            model_path: 微調後的 Pop2Piano 模型路徑（可選）
                       如果提供，將使用微調模型而非預設模型
            progress_callback: 進度回調函數，接收 (progress: int, message: str)
        """
        self._pop2piano_model = None
        self._pop2piano_processor = None
        self._bytedance_transcriptor = None
        self._custom_model_path = model_path
        self._progress_callback = progress_callback

        # Composer style labels
        self._composer_styles = {
            "composer2": "Simple & Clean (簡單清晰)",
            "composer4": "Balanced (平衡推薦) ⭐",
            "composer7": "Rich & Complex (豐富複雜)",
            "composer10": "Moderate (中等難度)",
            "composer15": "Full Arrangement (完整編曲)",
            "composer20": "Advanced (進階)",
        }

    def audio_to_midi(self, audio_path: str, mode: str = "auto", composer: str = "auto") -> "pretty_midi.PrettyMIDI":
        """將音訊轉為鋼琴 MIDI
        
        Args:
            audio_path: 音訊檔案路徑
            mode: 轉錄模式
                - "auto": 自動選擇（預設使用 pop2piano）
                - "hybrid": 混合模式 - Basic Pitch 旋律 + 自動生成伴奏（推薦）
                - "pop2piano": 流行音樂轉鋼琴編曲
                - "pop2piano_fast": 快速模式（只測試 5 個 composer）
                - "bytedance": 高精度鋼琴轉錄
                - "basic_pitch": 通用音高檢測
            composer: Pop2Piano 編曲風格
                - "auto": 自動選擇最佳（測試所有 21 種）
                - "top5": 測試前 5 個最常用的 composer
                - "composer1" ~ "composer21": 指定風格
        """
        if mode == "auto":
            mode = "pop2piano"
            composer = "composer2"  # Use simpler composer for cleaner sheets
        
        if mode == "hybrid":
            try:
                return self._hybrid_transcribe(audio_path)
            except Exception as e:
                logger.error(f"Hybrid transcription failed: {e}")
                import traceback
                traceback.print_exc()
                # Fallback to pop2piano
                mode = "pop2piano"
        
        if mode == "bytedance":
            try:
                return self._bytedance_transcribe(audio_path)
            except Exception as e:
                logger.error(f"ByteDance transcription failed: {e}")
                import traceback
                traceback.print_exc()
        
        if mode in ("pop2piano", "pop2piano_fast"):
            try:
                fast_mode = (mode == "pop2piano_fast")
                return self._pop2piano_convert(audio_path, composer=composer, fast_mode=fast_mode)
            except Exception as e:
                logger.error(f"Pop2Piano failed: {e}")
                import traceback
                traceback.print_exc()

        # Fallback 到 Basic Pitch
        try:
            return self._basic_pitch_predict(audio_path)
        except Exception as e:
            logger.error(f"Basic Pitch failed: {e}")

        # 最後 fallback 到 demo
        logger.warning("All transcription methods failed, returning demo MIDI")
        return self._generate_demo_midi()

    def _hybrid_transcribe(self, audio_path: str) -> "pretty_midi.PrettyMIDI":
        """混合模式：Basic Pitch 提取旋律 + 自動生成和弦伴奏
        
        這個方法解決 Pop2Piano 的三個主要問題：
        1. 旋律缺失 → 用 Basic Pitch 準確提取
        2. 節奏混亂 → 強制量化到拍子網格
        3. 太雜亂 → 簡化伴奏，只保留主要和弦
        """
        import librosa
        import pretty_midi as pm
        import numpy as np
        from basic_pitch.inference import predict
        
        logger.info("Hybrid mode: Extracting melody with Basic Pitch...")
        
        # 1. 用 Basic Pitch 提取所有音符（它對旋律很準）
        _, raw_midi, _ = predict(
            audio_path,
            onset_threshold=0.5,
            frame_threshold=0.3,
            minimum_note_length=58,  # 更短的最小音符長度
        )
        
        # 2. 載入音訊分析節拍
        audio, sr = librosa.load(audio_path, sr=22050)
        tempo, beats = librosa.beat.beat_track(y=audio, sr=sr)
        tempo = float(tempo) if isinstance(tempo, (int, float, np.floating)) else float(tempo[0]) if hasattr(tempo, '__len__') else 120.0
        
        logger.info(f"  Detected tempo: {tempo:.1f} BPM")
        
        # 3. 收集所有音符
        all_notes = []
        for inst in raw_midi.instruments:
            all_notes.extend(inst.notes)
        
        if not all_notes:
            logger.warning("  No notes detected!")
            return self._generate_demo_midi()
        
        logger.info(f"  Raw notes: {len(all_notes)}")
        
        # 4. 分離旋律和伴奏音符
        melody_notes, bass_notes = self._separate_melody_and_bass(all_notes, tempo)
        
        logger.info(f"  Melody notes: {len(melody_notes)}, Bass notes: {len(bass_notes)}")
        
        # 5. 量化到拍子網格
        beat_duration = 60.0 / tempo
        eighth = beat_duration / 2
        
        # 6. 建立輸出 MIDI
        new_midi = pm.PrettyMIDI(initial_tempo=tempo)
        right_hand = pm.Instrument(program=0, name="Right Hand")
        left_hand = pm.Instrument(program=0, name="Left Hand")
        
        # 7. 處理旋律（右手）- 量化並清理
        for note in melody_notes:
            q_start = round(note.start / eighth) * eighth
            q_end = round(note.end / eighth) * eighth
            if q_end <= q_start:
                q_end = q_start + eighth
            
            new_note = pm.Note(
                velocity=80,
                pitch=note.pitch,
                start=q_start,
                end=q_end
            )
            right_hand.notes.append(new_note)
        
        # 8. 生成簡化的左手伴奏（基於檢測到的低音）
        left_hand.notes = self._generate_simple_accompaniment(bass_notes, tempo, beat_duration)
        
        # 9. 清理重複音符
        right_hand.notes = self._remove_duplicate_notes(right_hand.notes)
        left_hand.notes = self._remove_duplicate_notes(left_hand.notes)
        
        new_midi.instruments.append(right_hand)
        new_midi.instruments.append(left_hand)
        
        total_notes = len(right_hand.notes) + len(left_hand.notes)
        logger.info(f"  Final output: {total_notes} notes")
        
        return new_midi
    
    def _separate_melody_and_bass(self, notes: list, tempo: float) -> tuple:
        """分離旋律和低音
        
        旋律特徵：
        - 較高音域 (通常 > C4/60)
        - 單音線條
        - 較長的音符
        
        低音特徵：
        - 較低音域 (通常 < C4/60)
        - 通常在強拍
        """
        from collections import defaultdict
        
        MELODY_THRESHOLD = 60  # Middle C
        
        # 按時間分組
        time_groups = defaultdict(list)
        for note in notes:
            key = round(note.start, 2)
            time_groups[key].append(note)
        
        melody_notes = []
        bass_notes = []
        
        for time_key in sorted(time_groups.keys()):
            group = time_groups[time_key]
            
            # 分離高低音
            high_notes = [n for n in group if n.pitch >= MELODY_THRESHOLD]
            low_notes = [n for n in group if n.pitch < MELODY_THRESHOLD]
            
            # 旋律：取最高音（通常是主旋律）
            if high_notes:
                highest = max(high_notes, key=lambda n: n.pitch)
                melody_notes.append(highest)
            
            # 低音：取最低音
            if low_notes:
                lowest = min(low_notes, key=lambda n: n.pitch)
                bass_notes.append(lowest)
        
        return melody_notes, bass_notes
    
    def _generate_simple_accompaniment(self, bass_notes: list, tempo: float, beat_duration: float) -> list:
        """生成簡化的左手伴奏
        
        策略：
        1. 每小節只放 2-4 個和弦
        2. 基於檢測到的低音推測和弦
        3. 使用常見的流行音樂伴奏模式
        """
        import pretty_midi as pm
        
        if not bass_notes:
            return []
        
        result = []
        half_beat = beat_duration / 2
        
        # 按小節分組（假設 4/4 拍）
        measure_duration = beat_duration * 4
        
        # 收集每個時間點的低音
        bass_by_time = {}
        for note in bass_notes:
            q_time = round(note.start / beat_duration) * beat_duration
            if q_time not in bass_by_time or note.pitch < bass_by_time[q_time]:
                bass_by_time[q_time] = note.pitch
        
        # 為每個低音生成簡單的八度或五度
        for time, pitch in sorted(bass_by_time.items()):
            # 確保在鋼琴低音範圍內
            while pitch > 55:
                pitch -= 12
            while pitch < 36:
                pitch += 12
            
            # 主音
            root = pm.Note(
                velocity=70,
                pitch=pitch,
                start=time,
                end=time + beat_duration * 0.9
            )
            result.append(root)
            
            # 偶爾加五度（每隔一拍）
            beat_num = int(time / beat_duration) % 4
            if beat_num in (0, 2):  # 強拍加五度
                fifth = pm.Note(
                    velocity=60,
                    pitch=pitch + 7,
                    start=time,
                    end=time + beat_duration * 0.9
                )
                result.append(fifth)
        
        return result

    def _bytedance_transcribe(self, audio_path: str) -> "pretty_midi.PrettyMIDI":
        """使用 ByteDance 高精度鋼琴轉錄
        
        這是目前最準確的鋼琴轉錄模型，適合：
        - 鋼琴獨奏錄音
        - 鋼琴為主的音樂
        - 需要高精度轉錄的場景
        """
        import librosa
        import pretty_midi as pm
        from piano_transcription_inference import PianoTranscription, sample_rate
        import tempfile
        import os
        
        # 載入模型（首次會下載約 400MB）
        if self._bytedance_transcriptor is None:
            logger.info("Loading ByteDance Piano Transcription model...")
            # 使用 CPU 以確保相容性，GPU 用戶可改為 'cuda'
            self._bytedance_transcriptor = PianoTranscription(
                device='cpu',  # 改為 'cuda' 如果有 GPU
                checkpoint_path=None  # 自動下載
            )
            logger.info("ByteDance model loaded!")
        
        # 載入音訊（ByteDance 模型使用 16kHz）
        audio, _ = librosa.load(audio_path, sr=sample_rate, mono=True)
        
        # 轉錄到臨時 MIDI 檔案
        with tempfile.NamedTemporaryFile(suffix='.mid', delete=False) as tmp:
            tmp_path = tmp.name
        
        try:
            self._bytedance_transcriptor.transcribe(audio, tmp_path)
            
            # 讀取生成的 MIDI
            midi = pm.PrettyMIDI(tmp_path)
            
            # 後處理：分離左右手
            cleaned_midi = self._split_hands(midi)
            
            note_count = sum(len(inst.notes) for inst in cleaned_midi.instruments)
            logger.info(f"ByteDance output: {note_count} notes")
            
            return cleaned_midi
        finally:
            # 清理臨時檔案
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
    
    def _split_hands(self, midi: "pretty_midi.PrettyMIDI") -> "pretty_midi.PrettyMIDI":
        """將單軌 MIDI 分離為左右手"""
        import pretty_midi as pm
        
        # 收集所有音符
        all_notes = []
        for inst in midi.instruments:
            all_notes.extend(inst.notes)
        
        if not all_notes:
            return midi
        
        # 取得 tempo
        tempo_changes = midi.get_tempo_changes()
        tempo = float(tempo_changes[1][0]) if len(tempo_changes[1]) > 0 else 120.0
        
        # 建立新的雙手 MIDI
        new_midi = pm.PrettyMIDI(initial_tempo=tempo)
        right_hand = pm.Instrument(program=0, name="Right Hand")
        left_hand = pm.Instrument(program=0, name="Left Hand")
        
        SPLIT_POINT = 60  # Middle C
        
        for note in all_notes:
            new_note = pm.Note(
                velocity=note.velocity,
                pitch=note.pitch,
                start=note.start,
                end=note.end,
            )
            
            if note.pitch >= SPLIT_POINT:
                right_hand.notes.append(new_note)
            else:
                left_hand.notes.append(new_note)
        
        new_midi.instruments.append(right_hand)
        new_midi.instruments.append(left_hand)
        return new_midi

    def _pop2piano_convert(self, audio_path: str, composer: str = "auto", fast_mode: bool = False) -> "pretty_midi.PrettyMIDI":
        """使用 Pop2Piano 產生鋼琴編曲
        
        Pop2Piano 有 21 種編曲風格（composer1-21），每種代表不同 YouTube 鋼琴家的風格：
        - composer1-5: 較簡單的編曲
        - composer6-12: 中等複雜度
        - composer13-21: 較豐富的編曲
        
        Args:
            audio_path: 音訊檔案路徑
            composer: 編曲風格
                - "auto": 測試所有 21 種，選最佳
                - "top5": 測試前 5 個常用風格
                - "composer1" ~ "composer21": 指定風格
            fast_mode: 快速模式，只測試 5 個代表性 composer
        """
        import librosa
        import pretty_midi as pm
        from transformers import Pop2PianoForConditionalGeneration, Pop2PianoProcessor

        # 載入模型（首次會下載約 1.5GB）
        if self._pop2piano_model is None:
            model_source = self._custom_model_path or "sweetcocoa/pop2piano"
            logger.info(f"Loading Pop2Piano model from: {model_source}")
            
            self._pop2piano_processor = Pop2PianoProcessor.from_pretrained(
                model_source if self._custom_model_path else "sweetcocoa/pop2piano"
            )
            self._pop2piano_model = Pop2PianoForConditionalGeneration.from_pretrained(
                model_source
            )
            
            # 嘗試移動到 GPU
            import torch
            if torch.cuda.is_available():
                self._pop2piano_model = self._pop2piano_model.cuda()
                logger.info("Pop2Piano model loaded on GPU!")
            else:
                logger.info("Pop2Piano model loaded on CPU (GPU not available)")
            
            # 啟用記憶體優化
            self._pop2piano_model.eval()

        # 檢查音訊長度，長檔案需要特殊處理
        duration = self.get_duration(audio_path)
        max_chunk_duration = 180  # 最多 3 分鐘一段
        
        if duration > max_chunk_duration:
            logger.info(f"長音訊檢測 ({duration:.0f}s)，分段處理...")
            return self._pop2piano_chunked(audio_path, composer, fast_mode, max_chunk_duration)

        # 載入音訊 (44.1kHz 是 Pop2Piano 推薦的取樣率)
        audio, sr = librosa.load(audio_path, sr=44100)

        # 處理音訊
        inputs = self._pop2piano_processor(
            audio=audio,
            sampling_rate=sr,
            return_tensors="pt"
        )

        # 移動到 GPU 如果可用
        import torch
        if torch.cuda.is_available():
            inputs = {k: v.cuda() if hasattr(v, 'cuda') else v for k, v in inputs.items()}

        if composer not in ("auto", "top3", "top5"):
            # 使用指定的 composer
            midi = self._generate_with_composer(inputs, composer)
            return self._enhanced_cleanup(midi)
        
        # 自動選擇：測試多種 composer 風格，選擇最佳結果
        if composer == "top3":
            # 測試前 3 個最佳風格（更快）
            composers_to_try = ["composer4", "composer7", "composer10"]
            logger.info("Testing top 3 composer styles...")
        elif composer == "top5" or fast_mode:
            # 測試前 5 個常用風格
            composers_to_try = ["composer2", "composer4", "composer7", "composer10", "composer15"]
            logger.info("Testing top 5 composer styles...")
        else:
            # 完整模式：測試所有 21 種風格
            composers_to_try = [f"composer{i}" for i in range(1, 22)]
            logger.info("Testing all 21 composer styles...")
        
        best_midi = None
        best_score = -1
        best_composer = None
        results = []
        
        for comp in composers_to_try:
            try:
                midi = self._generate_with_composer(inputs, comp)
                score = self._evaluate_arrangement_quality(midi)
                results.append((comp, score))
                
                if score > best_score:
                    best_score = score
                    best_midi = midi
                    best_composer = comp
                    
            except Exception as e:
                logger.warning(f"  {comp} failed: {e}")
                continue
        
        # 顯示排名
        results.sort(key=lambda x: x[1], reverse=True)
        logger.info("\nComposer ranking:")
        for comp, score in results[:5]:
            marker = " ← BEST" if comp == best_composer else ""
            style = self._composer_styles.get(comp, "")
            logger.info(f"  {comp}: {score:.1f} {style}{marker}")
        
        if best_midi is None:
            # Fallback 到 composer4
            best_midi = self._generate_with_composer(inputs, "composer4")
        
        # 後處理：分離左右手 + 清理
        cleaned_midi = self._enhanced_cleanup(best_midi)
        
        note_count = sum(len(inst.notes) for inst in cleaned_midi.instruments)
        logger.info(f"\nPop2Piano final output: {note_count} notes (using {best_composer})")
        
        return cleaned_midi
    
    def _pop2piano_chunked(self, audio_path: str, composer: str, fast_mode: bool, chunk_duration: int) -> "pretty_midi.PrettyMIDI":
        """分段處理長音訊"""
        import librosa
        import pretty_midi as pm
        import numpy as np

        def _report(progress: int, message: str):
            """Report progress"""
            if self._progress_callback:
                self._progress_callback(progress, message)
            logger.info(f"Progress {progress}%: {message}")

        # 載入整個音訊
        audio, sr = librosa.load(audio_path, sr=44100, mono=True)
        total_duration = len(audio) / sr

        # 處理每一段
        all_notes = []
        num_chunks = int(np.ceil(total_duration / chunk_duration))

        for i in range(num_chunks):
            start_sample = i * chunk_duration * sr
            end_sample = min((i + 1) * chunk_duration * sr, len(audio))

            chunk_audio = audio[start_sample:end_sample]
            chunk_start_time = start_sample / sr

            # 計算進度：15% + (i/num_chunks) * 60%
            chunk_progress = 15 + int((i / num_chunks) * 60)
            _report(chunk_progress, f"AI 分析段落 {i+1}/{num_chunks}...")

            logger.info(f"  處理段落 {i+1}/{num_chunks} ({chunk_start_time:.0f}s - {end_sample/sr:.0f}s)...")

            # 處理這一段
            inputs = self._pop2piano_processor(
                audio=chunk_audio,
                sampling_rate=sr,
                return_tensors="pt"
            )

            # 移動到 GPU
            import torch
            if torch.cuda.is_available():
                inputs = {k: v.cuda() for k, v in inputs.items()}

            # 生成 MIDI
            try:
                midi = self._generate_with_composer(inputs, composer)
                # 調整時間偏移
                for inst in midi.instruments:
                    for note in inst.notes:
                        note.start += chunk_start_time
                        note.end += chunk_start_time
                        all_notes.append(note)
            except Exception as e:
                logger.warning(f"    段落 {i+1} 失敗: {e}")
                continue

        # 合併所有音符
        if not all_notes:
            return self._generate_demo_midi()
        
        # 建立最終 MIDI
        final_midi = pm.PrettyMIDI(initial_tempo=120)
        piano = pm.Instrument(program=0, name="Piano")
        piano.notes = all_notes
        final_midi.instruments.append(piano)
        
        return self._enhanced_cleanup(final_midi)
    
    def _generate_with_composer(self, inputs, composer: str) -> "pretty_midi.PrettyMIDI":
        """使用指定 composer 生成 MIDI"""
        import torch
        
        generate_kwargs = {
            "input_features": inputs["input_features"],
            "composer": composer,
            "max_length": 2048,
            "num_beams": 3,
        }
        if "attention_mask" in inputs:
            generate_kwargs["attention_mask"] = inputs["attention_mask"]

        # 生成
        with torch.no_grad():
            model_output = self._pop2piano_model.generate(**generate_kwargs)

        # 處理 GPU 輸出
        if torch.cuda.is_available():
            model_output = model_output.cpu()

        midi_output = self._pop2piano_processor.batch_decode(
            token_ids=model_output,
            feature_extractor_output=inputs,
        )

        return midi_output["pretty_midi_objects"][0]
    
    def _evaluate_arrangement_quality(self, midi) -> float:
        """評估編曲品質
        
        評分標準：
        1. 音符密度：每秒 3-6 個音符最佳
        2. 音域分布：左右手都有音符
        3. 和弦豐富度：有適當的和弦
        4. 旋律連貫性：音符之間有合理的間隔
        """
        all_notes = []
        for inst in midi.instruments:
            all_notes.extend(inst.notes)
        
        if not all_notes:
            return 0
        
        duration = midi.get_end_time() or 1
        note_count = len(all_notes)
        notes_per_second = note_count / duration
        
        # 1. 音符密度評分 (最佳: 3-6 notes/sec)
        if 3 <= notes_per_second <= 6:
            density_score = 1.0
        elif 2 <= notes_per_second <= 8:
            density_score = 0.7
        elif 1 <= notes_per_second <= 10:
            density_score = 0.4
        else:
            density_score = 0.1
        
        # 2. 音域分布評分
        pitches = [n.pitch for n in all_notes]
        has_bass = any(p < 60 for p in pitches)
        has_treble = any(p >= 60 for p in pitches)
        range_score = 1.0 if (has_bass and has_treble) else 0.5
        
        # 3. 和弦豐富度（同時發聲的音符）
        from collections import defaultdict
        time_groups = defaultdict(list)
        for note in all_notes:
            key = round(note.start, 2)
            time_groups[key].append(note)
        
        chord_counts = [len(g) for g in time_groups.values()]
        avg_chord_size = sum(chord_counts) / len(chord_counts) if chord_counts else 1
        
        # 最佳和弦大小: 2-4
        if 2 <= avg_chord_size <= 4:
            chord_score = 1.0
        elif 1.5 <= avg_chord_size <= 5:
            chord_score = 0.7
        else:
            chord_score = 0.4
        
        # 綜合評分
        total_score = (density_score * 0.4 + range_score * 0.3 + chord_score * 0.3) * note_count
        
        return total_score

    def _enhanced_cleanup(self, midi: "pretty_midi.PrettyMIDI") -> "pretty_midi.PrettyMIDI":
        """增強版清理：分離左右手 + 量化 + 力度正規化
        
        目標：產生更接近 PopPianoAI 品質的輸出
        使用統一的量化策略，確保時值一致性
        """
        import pretty_midi as pm
        
        # 收集所有音符
        all_notes = []
        for inst in midi.instruments:
            all_notes.extend(inst.notes)
        
        if not all_notes:
            return midi
        
        # 取得原始 tempo
        tempo_changes = midi.get_tempo_changes()
        tempo = float(tempo_changes[1][0]) if len(tempo_changes[1]) > 0 else 120.0
        
        # 建立新的雙手 MIDI
        new_midi = pm.PrettyMIDI(initial_tempo=tempo)
        right_hand = pm.Instrument(program=0, name="Right Hand")
        left_hand = pm.Instrument(program=0, name="Left Hand")
        
        # 量化參數
        beat_duration = 60.0 / tempo
        sixteenth = beat_duration / 4
        
        # 分離左右手
        SPLIT_POINT = 60  # Middle C
        
        # 量化並過濾
        for note in all_notes:
            if note.velocity < 15:  # 過濾極弱音符
                continue
            if note.end <= note.start:
                continue
            
            # 輕量量化到 16 分音符網格
            quantized_start = round(note.start / sixteenth) * sixteenth
            quantized_end = round(note.end / sixteenth) * sixteenth
            
            # 確保最小時值（至少 50% 網格）
            min_duration = sixteenth * 0.5
            if quantized_end <= quantized_start:
                quantized_end = quantized_start + sixteenth
            
            # 確保音符時值合理
            raw_duration = quantized_end - quantized_start
            quarter_duration = beat_duration
            rounded_duration = self._round_to_standard_duration(raw_duration, quarter_duration)
            quantized_end = quantized_start + rounded_duration
            
            # 力度正規化到 60-100 範圍（更自然的動態範圍）
            normalized_velocity = int(60 + (note.velocity / 127) * 40)
            normalized_velocity = max(60, min(100, normalized_velocity))
            
            new_note = pm.Note(
                velocity=normalized_velocity,
                pitch=note.pitch,
                start=quantized_start,
                end=quantized_end,
            )
            
            if note.pitch >= SPLIT_POINT:
                right_hand.notes.append(new_note)
            else:
                left_hand.notes.append(new_note)
        
        # 移除重複音符
        right_hand.notes = self._remove_duplicate_notes(right_hand.notes)
        left_hand.notes = self._remove_duplicate_notes(left_hand.notes)
        
        # 限制同時發聲的音符數（避免過於密集）
        right_hand.notes = self._limit_simultaneous_notes(right_hand.notes, max_notes=4)
        left_hand.notes = self._limit_simultaneous_notes(left_hand.notes, max_notes=3)
        
        new_midi.instruments.append(right_hand)
        new_midi.instruments.append(left_hand)
        return new_midi
    
    def _round_to_standard_duration(self, duration: float, quarter_duration: float) -> float:
        """將時值四捨五入到最接近的標準時值（與 midi_converter 保持一致）"""
        # 以 16 分音符為單位計算
        sixteenths = duration / quarter_duration * 4
        
        # 標準時值（以 16 分音符為單位）
        standards = [16, 12, 8, 6, 4, 3, 2, 1, 0.5]
        
        # 找最接近的
        closest = min(standards, key=lambda s: abs(s - sixteenths))
        
        return closest * quarter_duration / 4
    
    def _limit_simultaneous_notes(self, notes: list, max_notes: int = 4) -> list:
        """限制同時發聲的音符數量"""
        if not notes:
            return notes
        
        # 按時間分組
        from collections import defaultdict
        time_groups = defaultdict(list)
        
        for note in notes:
            # 量化到小數點後 2 位
            key = round(note.start, 2)
            time_groups[key].append(note)
        
        result = []
        for time_key in sorted(time_groups.keys()):
            group = time_groups[time_key]
            # 保留力度最強的 N 個音符
            group.sort(key=lambda n: n.velocity, reverse=True)
            result.extend(group[:max_notes])
        
        return result
    
    def _remove_duplicate_notes(self, notes: list) -> list:
        """移除重複音符"""
        seen = set()
        unique_notes = []
        
        for note in sorted(notes, key=lambda n: (n.start, n.pitch)):
            key = (round(note.start, 3), note.pitch)
            if key not in seen:
                seen.add(key)
                unique_notes.append(note)
        
        return unique_notes

    def _basic_pitch_predict(self, audio_path: str) -> "pretty_midi.PrettyMIDI":
        """使用 Basic Pitch 進行原始轉錄（fallback）"""
        from basic_pitch.inference import predict

        _, midi_data, _ = predict(
            audio_path,
            onset_threshold=0.5,
            frame_threshold=0.3,
            minimum_note_length=80,
        )
        return midi_data

    def _generate_demo_midi(self) -> "pretty_midi.PrettyMIDI":
        """產生示範 MIDI（最終 fallback）"""
        import pretty_midi as pm

        midi = pm.PrettyMIDI(initial_tempo=120)
        piano = pm.Instrument(program=0, name="Piano")

        melody_notes = [
            (60, 0.0), (60, 0.5), (67, 1.0), (67, 1.5),
            (69, 2.0), (69, 2.5), (67, 3.0),
            (65, 4.0), (65, 4.5), (64, 5.0), (64, 5.5),
            (62, 6.0), (62, 6.5), (60, 7.0),
        ]
        for pitch, start in melody_notes:
            duration = 1.0 if start == 3.0 or start == 7.0 else 0.45
            note = pm.Note(velocity=80, pitch=pitch, start=start, end=start + duration)
            piano.notes.append(note)

        bass_notes = [
            (48, 0.0), (43, 1.0), (45, 2.0), (48, 3.0),
            (41, 4.0), (43, 5.0), (48, 6.0), (48, 7.0),
        ]
        for pitch, start in bass_notes:
            note = pm.Note(velocity=60, pitch=pitch, start=start, end=start + 0.9)
            piano.notes.append(note)

        midi.instruments.append(piano)
        return midi

    def get_duration(self, audio_path: str) -> float:
        """取得音訊長度"""
        try:
            import librosa
            duration: float = librosa.get_duration(path=audio_path)
            return duration
        except Exception:
            import os
            file_size = os.path.getsize(audio_path)
            estimated_duration = file_size / 16000.0
            return max(estimated_duration, 1.0)
