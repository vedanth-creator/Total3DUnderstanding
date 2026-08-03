"""FFmpeg-based extraction of deterministic, ordered video frames."""

from pathlib import Path
from typing import List

from reconstruction.config import ReconstructionConfig
from reconstruction.process_runner import ProcessRunner


class FrameExtractionError(RuntimeError):
    pass


class FrameExtractor:
    def __init__(self, process_runner: ProcessRunner) -> None:
        self.process_runner = process_runner

    def extract(self, config: ReconstructionConfig) -> List[Path]:
        if not config.video_path.is_file():
            raise FrameExtractionError(
                "Input video does not exist or is not a file: %s" % config.video_path
            )

        output_pattern = config.images_directory / "frame_%08d.jpg"
        frame_rate = format(config.frames_per_second, ".12g")
        scale_filter = (
            "fps=%s,scale='min(iw,%d)':'min(ih,%d)':"
            "force_original_aspect_ratio=decrease"
            % (frame_rate, config.max_image_size, config.max_image_size)
        )
        arguments = [
            config.ffmpeg_binary,
            "-hide_banner",
            "-loglevel",
            "info",
            "-y",
            "-i",
            str(config.video_path),
            "-vf",
            scale_filter,
            "-q:v",
            "2",
            "-start_number",
            "0",
            str(output_pattern),
        ]
        self.process_runner.run(
            arguments,
            log_path=config.logs_directory / "ffmpeg-frame-extraction.log",
            cwd=config.job_directory,
        )

        frames = sorted(config.images_directory.glob("frame_*.jpg"))
        if not frames:
            raise FrameExtractionError(
                "FFmpeg completed without producing any extracted frames."
            )
        return frames
