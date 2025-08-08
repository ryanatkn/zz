// Raylib Audio Module (raudio)
// Audio device management, sound operations, music streaming, wave manipulation
const types = @import("raylib_types.zig");

// Import types for internal use
const Wave = types.Wave;
const Sound = types.Sound;
const Music = types.Music;
const AudioStream = types.AudioStream;

//----------------------------------------------------------------------------------
// Audio Functions (extern functions)
//----------------------------------------------------------------------------------

// Audio device management functions
pub extern fn InitAudioDevice() void;
pub extern fn CloseAudioDevice() void;
pub extern fn IsAudioDeviceReady() bool;
pub extern fn SetMasterVolume(volume: f32) void;
pub extern fn GetMasterVolume() f32;

// Wave/Sound loading/unloading functions
pub extern fn LoadWave(fileName: [*:0]const u8) Wave;
pub extern fn LoadWaveFromMemory(fileType: [*:0]const u8, fileData: [*c]const u8, dataSize: c_int) Wave;
pub extern fn IsWaveValid(wave: Wave) bool;
pub extern fn LoadSound(fileName: [*:0]const u8) Sound;
pub extern fn LoadSoundFromWave(wave: Wave) Sound;
pub extern fn LoadSoundAlias(source: Sound) Sound;
pub extern fn IsSoundValid(sound: Sound) bool;
pub extern fn UpdateSound(sound: Sound, data: ?*const anyopaque, sampleCount: c_int) void;
pub extern fn UnloadWave(wave: Wave) void;
pub extern fn UnloadSound(sound: Sound) void;
pub extern fn UnloadSoundAlias(alias: Sound) void;
pub extern fn ExportWave(wave: Wave, fileName: [*:0]const u8) bool;
pub extern fn ExportWaveAsCode(wave: Wave, fileName: [*:0]const u8) bool;

// Wave/Sound management functions
pub extern fn PlaySound(sound: Sound) void;
pub extern fn StopSound(sound: Sound) void;
pub extern fn PauseSound(sound: Sound) void;
pub extern fn ResumeSound(sound: Sound) void;
pub extern fn IsSoundPlaying(sound: Sound) bool;
pub extern fn SetSoundVolume(sound: Sound, volume: f32) void;
pub extern fn SetSoundPitch(sound: Sound, pitch: f32) void;
pub extern fn SetSoundPan(sound: Sound, pan: f32) void;
pub extern fn WaveCopy(wave: Wave) Wave;
pub extern fn WaveCrop(wave: *Wave, initFrame: c_int, finalFrame: c_int) void;
pub extern fn WaveFormat(wave: *Wave, sampleRate: c_int, sampleSize: c_int, channels: c_int) void;
pub extern fn LoadWaveSamples(wave: Wave) [*]f32;
pub extern fn UnloadWaveSamples(samples: [*]f32) void;

// Music management functions
pub extern fn LoadMusicStream(fileName: [*:0]const u8) Music;
pub extern fn LoadMusicStreamFromMemory(fileType: [*:0]const u8, data: [*c]const u8, dataSize: c_int) Music;
pub extern fn IsMusicValid(music: Music) bool;
pub extern fn UnloadMusicStream(music: Music) void;
pub extern fn PlayMusicStream(music: Music) void;
pub extern fn IsMusicStreamPlaying(music: Music) bool;
pub extern fn UpdateMusicStream(music: Music) void;
pub extern fn StopMusicStream(music: Music) void;
pub extern fn PauseMusicStream(music: Music) void;
pub extern fn ResumeMusicStream(music: Music) void;
pub extern fn SeekMusicStream(music: Music, position: f32) void;
pub extern fn SetMusicVolume(music: Music, volume: f32) void;
pub extern fn SetMusicPitch(music: Music, pitch: f32) void;
pub extern fn SetMusicPan(music: Music, pan: f32) void;
pub extern fn GetMusicTimeLength(music: Music) f32;
pub extern fn GetMusicTimePlayed(music: Music) f32;

// AudioStream management functions
pub extern fn LoadAudioStream(sampleRate: c_uint, sampleSize: c_uint, channels: c_uint) AudioStream;
pub extern fn IsAudioStreamValid(stream: AudioStream) bool;
pub extern fn UnloadAudioStream(stream: AudioStream) void;
pub extern fn UpdateAudioStream(stream: AudioStream, data: ?*const anyopaque, frameCount: c_int) void;
pub extern fn IsAudioStreamProcessed(stream: AudioStream) bool;
pub extern fn PlayAudioStream(stream: AudioStream) void;
pub extern fn PauseAudioStream(stream: AudioStream) void;
pub extern fn ResumeAudioStream(stream: AudioStream) void;
pub extern fn IsAudioStreamPlaying(stream: AudioStream) bool;
pub extern fn StopAudioStream(stream: AudioStream) void;
pub extern fn SetAudioStreamVolume(stream: AudioStream, volume: f32) void;
pub extern fn SetAudioStreamPitch(stream: AudioStream, pitch: f32) void;
pub extern fn SetAudioStreamPan(stream: AudioStream, pan: f32) void;
pub extern fn SetAudioStreamBufferSizeDefault(size: c_int) void;

