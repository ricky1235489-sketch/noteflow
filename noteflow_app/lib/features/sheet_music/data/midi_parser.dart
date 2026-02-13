import 'dart:typed_data';
import '../domain/music_note.dart';

/// MIDI 解析結果
class MidiParseResult {
  final List<MusicNote> notes;
  final double tempo; // BPM
  final int beatsPerMeasure;
  final int beatUnit;

  const MidiParseResult({
    required this.notes,
    this.tempo = 120.0,
    this.beatsPerMeasure = 4,
    this.beatUnit = 4,
  });
}

/// 簡易 MIDI 檔案解析器
/// 解析 Standard MIDI File (SMF) 格式，提取音符事件
class MidiParser {
  static const int _middleC = 60;

  /// 解析 MIDI 二進位資料，回傳音符列表（向後相容）
  List<MusicNote> parse(Uint8List midiBytes) {
    return parseWithMeta(midiBytes).notes;
  }

  /// 解析 MIDI 二進位資料，回傳音符 + 元資料
  MidiParseResult parseWithMeta(Uint8List midiBytes) {
    final reader = _ByteReader(midiBytes);

    // 讀取 Header chunk
    final headerTag = reader.readString(4);
    if (headerTag != 'MThd') {
      throw FormatException('不是有效的 MIDI 檔案: $headerTag');
    }

    reader.readUint32(); // header length (always 6)
    final format = reader.readUint16();
    final numTracks = reader.readUint16();
    final division = reader.readUint16();

    final ticksPerBeat = division & 0x7FFF;

    final allNotes = <MusicNote>[];
    var tempo = 500000.0; // 預設 120 BPM (microseconds per beat)
    var beatsPerMeasure = 4;
    var beatUnit = 4;

    for (var track = 0; track < numTracks; track++) {
      final trackTag = reader.readString(4);
      if (trackTag != 'MTrk') {
        throw FormatException('無效的 Track chunk: $trackTag');
      }

      final trackLength = reader.readUint32();
      final trackEnd = reader.position + trackLength;

      var absoluteTick = 0;
      var runningStatus = 0;

      // 追蹤 note-on 事件以配對 note-off
      final activeNotes = <int, _NoteOnEvent>{};

      while (reader.position < trackEnd) {
        final deltaTicks = reader.readVariableLength();
        absoluteTick += deltaTicks;

        var statusByte = reader.readByte();

        // Running status
        if (statusByte < 0x80) {
          reader.position--;
          statusByte = runningStatus;
        } else {
          runningStatus = statusByte;
        }

        final messageType = statusByte & 0xF0;
        final channel = statusByte & 0x0F;

        switch (messageType) {
          case 0x90: // Note On
            final note = reader.readByte();
            final velocity = reader.readByte();
            if (velocity > 0) {
              activeNotes[note] = _NoteOnEvent(
                pitch: note,
                velocity: velocity,
                tick: absoluteTick,
                channel: channel,
              );
            } else {
              // velocity 0 = note off
              _finalizeNote(
                activeNotes, note, absoluteTick,
                ticksPerBeat, tempo, track, allNotes,
              );
            }
            break;

          case 0x80: // Note Off
            final note = reader.readByte();
            reader.readByte(); // velocity (ignored)
            _finalizeNote(
              activeNotes, note, absoluteTick,
              ticksPerBeat, tempo, track, allNotes,
            );
            break;

          case 0xA0: // Aftertouch
          case 0xB0: // Control Change
          case 0xE0: // Pitch Bend
            reader.readByte();
            reader.readByte();
            break;

          case 0xC0: // Program Change
          case 0xD0: // Channel Pressure
            reader.readByte();
            break;

          case 0xF0: // System / Meta
            if (statusByte == 0xFF) {
              final metaType = reader.readByte();
              final metaLength = reader.readVariableLength();

              if (metaType == 0x51 && metaLength == 3) {
                // Tempo change
                tempo = (reader.readByte() << 16 |
                    reader.readByte() << 8 |
                    reader.readByte())
                    .toDouble();
              } else if (metaType == 0x58 && metaLength == 4) {
                // Time Signature: nn dd cc bb
                beatsPerMeasure = reader.readByte();
                final dd = reader.readByte();
                beatUnit = 1 << dd; // dd is power of 2
                reader.readByte(); // MIDI clocks per metronome click
                reader.readByte(); // 32nd notes per MIDI quarter note
              } else {
                reader.skip(metaLength);
              }
            } else if (statusByte == 0xF0 || statusByte == 0xF7) {
              final sysexLength = reader.readVariableLength();
              reader.skip(sysexLength);
            }
            break;
        }
      }

      reader.position = trackEnd;
    }

    allNotes.sort((a, b) => a.startTime.compareTo(b.startTime));

    final bpm = 60000000.0 / tempo;
    return MidiParseResult(
      notes: allNotes,
      tempo: bpm,
      beatsPerMeasure: beatsPerMeasure,
      beatUnit: beatUnit,
    );
  }

  void _finalizeNote(
    Map<int, _NoteOnEvent> activeNotes,
    int pitch,
    int offTick,
    int ticksPerBeat,
    double tempo,
    int track,
    List<MusicNote> output,
  ) {
    final noteOn = activeNotes.remove(pitch);
    if (noteOn == null) return;

    final startTime = _ticksToSeconds(noteOn.tick, ticksPerBeat, tempo);
    final endTime = _ticksToSeconds(offTick, ticksPerBeat, tempo);

    // Use pitch-based hand assignment to match backend MusicXML generation.
    // Backend (sheet_generator.py) splits at MIDI pitch 60 (Middle C):
    //   pitch >= 60 → right hand (treble, staff 1)
    //   pitch <  60 → left hand (bass, staff 2)
    final hand = pitch >= _middleC ? 0 : 1;

    output.add(MusicNote(
      midiPitch: pitch,
      startTime: startTime,
      endTime: endTime,
      velocity: noteOn.velocity,
      hand: hand,
    ));
  }

  double _ticksToSeconds(int ticks, int ticksPerBeat, double microsecondsPerBeat) {
    return (ticks / ticksPerBeat) * (microsecondsPerBeat / 1000000.0);
  }
}

class _NoteOnEvent {
  final int pitch;
  final int velocity;
  final int tick;
  final int channel;

  const _NoteOnEvent({
    required this.pitch,
    required this.velocity,
    required this.tick,
    required this.channel,
  });
}

class _ByteReader {
  final Uint8List data;
  int position = 0;

  _ByteReader(this.data);

  int readByte() => data[position++];

  int readUint16() {
    final value = (data[position] << 8) | data[position + 1];
    position += 2;
    return value;
  }

  int readUint32() {
    final value = (data[position] << 24) |
        (data[position + 1] << 16) |
        (data[position + 2] << 8) |
        data[position + 3];
    position += 4;
    return value;
  }

  String readString(int length) {
    final bytes = data.sublist(position, position + length);
    position += length;
    return String.fromCharCodes(bytes);
  }

  int readVariableLength() {
    var value = 0;
    int byte;
    do {
      byte = readByte();
      value = (value << 7) | (byte & 0x7F);
    } while (byte & 0x80 != 0);
    return value;
  }

  void skip(int count) {
    position += count;
  }
}
