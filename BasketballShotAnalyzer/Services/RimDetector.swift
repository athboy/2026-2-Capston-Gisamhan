import CoreML
import Vision
import CoreMedia

final class RimDetector: @unchecked Sendable {
    private let request: VNCoreMLRequest

    init?() {
        // Xcode가 RimDetector.mlpackage를 빌드 시 RimDetector.mlmodelc로 컴파일해 번들에 넣어줌
        guard let url = Bundle.main.url(forResource: "RimDetector", withExtension: "mlmodelc") else {
            return nil
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all   // Neural Engine 사용
        guard let mlModel = try? MLModel(contentsOf: url, configuration: config),
              let visionModel = try? VNCoreMLModel(for: mlModel) else {
            return nil
        }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill   // YOLO 학습 입력(정사각 리사이즈)과 맞춤
        self.request = request
    }

    /// 프레임에서 림을 찾아 RimCalibration(중심 + 폭)으로 반환
    func detect(in sampleBuffer: CMSampleBuffer) -> RimCalibration? {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return nil }

        let objects = (request.results as? [VNRecognizedObjectObservation]) ?? []
        let rims = objects.filter { obs in
            guard let label = obs.labels.first?.identifier.lowercased() else { return false }
            return label.contains("rim") || label.contains("hoop") || label.contains("basket")
        }
        guard let best = rims.max(by: { $0.confidence < $1.confidence }),
              best.confidence >= 0.5 else { return nil }

        // boundingBox: 정규화 좌표, 원점 좌하단 (기존 코드의 좌표계와 동일)
        let box = best.boundingBox
        return RimCalibration(
            center: NormalizedPoint(x: box.midX, y: box.midY),
            widthFraction: box.width
        )
    }
}
