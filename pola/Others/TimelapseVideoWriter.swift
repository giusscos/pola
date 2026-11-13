import AVFoundation
import CoreImage
import UIKit

/// A finished "save as video" time lapse: the movie and the developed first frame for the print.
struct TimelapseVideo: Equatable, Sendable {
    let url: URL
    let thumbnailJPEG: Data
}

/// Writes a time-lapse video while it is being shot. Each frame is scaled down to the output size
/// and given the film look as it arrives, then appended to the movie, so a long time lapse never
/// holds more than the few frames waiting in the stream.
nonisolated enum TimelapseVideoWriter {
    static let maxDimension: CGFloat = 1080
    static let framesPerSecond: Int32 = 5
    private static let context = CIContext()

    /// Consumes `frames` until the stream finishes, then closes the movie.
    @concurrent
    static func write(frames: AsyncStream<UIImage>, film: FilmFilterEffect?, lens: Lens?) async -> TimelapseVideo? {
        var session: Session?
        var thumbnail: Data?
        for await frame in frames {
            guard let upright = uprightImage(frame) else { continue }
            if session == nil {
                session = Session(size: outputSize(for: upright.extent.size))
                // The print shows the first frame at full resolution, like a photo.
                thumbnail = await CaptureDevelopment.developedJPEG(from: frame, film: film, lens: lens)
            }
            guard let session else { break }
            let scaled = scaled(upright, toFill: session.size)
            let developed = FilmPipeline.apply(to: scaled, film: film, lens: lens, orientation: .up)
            await session.append(developed)
        }
        guard let session, let thumbnail, let url = await session.finish() else { return nil }
        return TimelapseVideo(url: url, thumbnailJPEG: thumbnail)
    }

    /// At most 1080 px on the longer side, with even dimensions as H.264 requires.
    private static func outputSize(for size: CGSize) -> CGSize {
        let scale = min(1, maxDimension / max(size.width, size.height))
        return CGSize(width: floor(size.width * scale / 2) * 2, height: floor(size.height * scale / 2) * 2)
    }

    /// The frame with its orientation baked into the pixels, at the origin.
    private static func uprightImage(_ image: UIImage) -> CIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let oriented = ciImage.oriented(CGImagePropertyOrientation(image.imageOrientation))
        return oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX,
                                                           y: -oriented.extent.minY))
    }

    private static func scaled(_ image: CIImage, toFill size: CGSize) -> CIImage {
        let extent = image.extent
        let scale = max(size.width / extent.width, size.height / extent.height)
        let resized = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1,
        ])
        let offset = CGAffineTransform(translationX: -(resized.extent.width - size.width) / 2 - resized.extent.minX,
                                       y: -(resized.extent.height - size.height) / 2 - resized.extent.minY)
        return resized.transformed(by: offset).cropped(to: CGRect(origin: .zero, size: size))
    }

    nonisolated private final class Session {
        let size: CGSize
        private let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        private let writer: AVAssetWriter?
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private var frameIndex: Int64 = 0

        init(size: CGSize) {
            self.size = size
            writer = try? AVAssetWriter(outputURL: url, fileType: .mov)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ])
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ])
            guard let writer, writer.canAdd(input) else { return }
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
        }

        func append(_ image: CIImage) async {
            guard let writer, writer.status == .writing, let buffer = makeBuffer() else { return }
            context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: size),
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(10))
            }
            let time = CMTime(value: frameIndex, timescale: TimelapseVideoWriter.framesPerSecond)
            if adaptor.append(buffer, withPresentationTime: time) {
                frameIndex += 1
            }
        }

        func finish() async -> URL? {
            guard let writer, writer.status == .writing, frameIndex > 0 else {
                writer?.cancelWriting()
                return nil
            }
            input.markAsFinished()
            await writer.finishWriting()
            return writer.status == .completed ? url : nil
        }

        private func makeBuffer() -> CVPixelBuffer? {
            var buffer: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
            } else {
                CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                    kCVPixelFormatType_32BGRA,
                                    [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]] as CFDictionary,
                                    &buffer)
            }
            return buffer
        }
    }
}
