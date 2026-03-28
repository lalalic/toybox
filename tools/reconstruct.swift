#!/usr/bin/env swift
//
// reconstruct.swift — Mac command-line photogrammetry tool
// Runs PhotogrammetrySession on a folder of images and outputs a USDZ model.
//
// Usage: swift reconstruct.swift <input-images-folder> <output.usdz>
//

import Foundation
import RealityKit

guard CommandLine.arguments.count >= 3 else {
    print("Usage: swift reconstruct.swift <input-images-folder> <output.usdz>")
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)

guard PhotogrammetrySession.isSupported else {
    print("ERROR: PhotogrammetrySession is not supported on this Mac.")
    exit(1)
}

// Count images
let fm = FileManager.default
let files = (try? fm.contentsOfDirectory(atPath: inputPath)) ?? []
let imageFiles = files.filter { $0.hasSuffix(".heic") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") || $0.hasSuffix(".png") }
print("Found \(imageFiles.count) images in \(inputPath)")

guard imageFiles.count >= 3 else {
    print("ERROR: Need at least 3 images, found \(imageFiles.count)")
    exit(1)
}

// Create output directory if needed
let outputDir = outputURL.deletingLastPathComponent()
try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

let detailStr = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : "reduced"
let detail: PhotogrammetrySession.Request.Detail
switch detailStr {
case "medium": detail = .medium
case "full": detail = .full
case "raw": detail = .raw
default: detail = .reduced
}
print("Detail level: \(detailStr)")

print("Creating PhotogrammetrySession...")
do {
    let session = try PhotogrammetrySession(input: inputURL)
    print("Session created, starting reconstruction...")

    try session.process(requests: [
        .modelFile(url: outputURL, detail: detail)
    ])

    // Monitor outputs
    for try await output in session.outputs {
        switch output {
        case .inputComplete:
            print("✓ Input complete - all images loaded")

        case .requestProgress(_, fractionComplete: let fraction):
            let pct = Int(fraction * 100)
            print("  Progress: \(pct)%")

        case .requestProgressInfo(_, let info):
            if let stage = info.processingStage {
                print("  Stage: \(stage)")
            }

        case .requestComplete(_, let result):
            print("✓ Request complete: \(result)")

        case .requestError(_, let error):
            print("✗ Request error: \(error)")
            exit(1)

        case .processingComplete:
            print("✓ Processing complete!")
            print("Output: \(outputURL.path)")
            exit(0)

        case .processingCancelled:
            print("✗ Processing cancelled")
            exit(1)

        case .invalidSample(let id, let reason):
            print("⚠ Invalid sample \(id): \(reason)")

        case .skippedSample(let id):
            print("⚠ Skipped sample: \(id)")

        case .automaticDownsampling:
            print("ℹ Automatic downsampling applied")

        case .stitchingIncomplete:
            print("⚠ Stitching incomplete")

        @unknown default:
            print("? Unknown output: \(output)")
        }
    }
} catch {
    print("ERROR: \(error)")
    exit(1)
}
