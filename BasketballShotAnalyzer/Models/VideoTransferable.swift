import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let fileManager = FileManager.default
            let tempDirectory = fileManager.temporaryDirectory
            let destination = tempDirectory.appendingPathComponent("shot-\(UUID().uuidString).\(fileExtension)")
            
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: received.file, to: destination)
            return VideoTransferable(url: destination)
        }
    }
}
