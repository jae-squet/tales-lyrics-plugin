// lib/lyrics/lyrics_state.dart

enum LyricsState {
  /// Lyrics feature is disabled / not requested
  idle,

  /// Checking for embedded tags / LRC file / cache
  checking,

  /// Whisper plugin pack not installed — prompt user to download
  noPack,

  /// Downloading plugin bundle from GitHub Releases
  downloadingPack,

  /// Installing (extracting) the downloaded bundle
  installingPack,

  /// Generating LRC from audio via local Whisper
  generating,

  /// Lyrics ready and synced to playback
  showing,

  /// Could not find or generate lyrics for this song
  notFound,

  /// An error occurred (message stored in provider)
  error,
}
