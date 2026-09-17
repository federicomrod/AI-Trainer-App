//
//  ScreenshotAttachment.swift
//  AI-Trainer
//
//  CLAUDE.md: "Screenshots: send the image to the model directly" --
//  Garmin Connect's own stats, a race entry, anything with no API to
//  pull from instead. This is the one shared piece both Today and
//  Coach chat need to turn a picked photo into what POST /turn wants:
//  a small base64 JPEG, not a multi-megabyte camera-roll original.
//
//  #if os(iOS): UIImage doesn't exist on the "My Mac" destination this
//  project's scheme can offer on Apple Silicon.

#if os(iOS)
import UIKit

extension UIImage {
    /// Downscaled and JPEG-compressed for a local-network POST and a
    /// reasonable image-token cost -- 1568px is Anthropic's own
    /// stated sweet spot, and OpenAI doesn't benefit from more either.
    func jpegBase64ForUpload(maxDimension: CGFloat = 1568, quality: CGFloat = 0.7) -> String? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}
#endif
