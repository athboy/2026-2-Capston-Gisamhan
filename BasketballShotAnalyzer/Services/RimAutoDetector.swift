import CoreML
import Vision
import CoreMedia

/// 새 모델(RimDetector.mlmodel)이 알려주는 이름표 2개.
/// 학습할 때 정한 이름과 글자 하나까지 똑같아야 해요.
private enum ModelLabel {
    static let ball = "ball"                 // 농구공 (지금은 쓰지 않아요)
    static let rim = "basketball rim"        // 림 (이것만 사용해요)

    /// 대소문자나 앞뒤 빈칸이 달라도 같은 이름으로 취급해요
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

final class RimAutoDetector: @unchecked Sendable {
    private let request: VNCoreMLRequest

    /// 이 확신도 이상일 때만 림으로 인정 (림을 못 찾으면 0.3 정도로 낮춰 보세요)
    private let minConfidence: Float = 0.5

    init?() {
        // Xcode가 RimDetector.mlmodel을 빌드할 때 RimDetector.mlmodelc로 바꿔 앱에 넣어줘요
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
        request.imageCropAndScaleOption = .scaleFill   // Create ML은 사진을 정사각형으로 늘려서 학습해요
        self.request = request
    }

    /// 프레임에서 림을 찾아 RimCalibration(중심 + 폭)으로 반환
    func detect(in sampleBuffer: CMSampleBuffer) -> RimCalibration? {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return nil }

        let objects = (request.results as? [VNRecognizedObjectObservation]) ?? []

        // 이름이 "basketball rim"과 정확히 같은 것만 림으로 인정 (ball은 제외)
        let rims = objects.filter { obs in
            guard let label = obs.labels.first?.identifier else { return false }
            return ModelLabel.normalized(label) == ModelLabel.rim
        }

        guard let best = rims.max(by: { $0.confidence < $1.confidence }),
              best.confidence >= minConfidence else { return nil }

        // boundingBox: 0~1 비율, 원점은 왼쪽 아래 (앱 좌표계와 같아요)
        let box = best.boundingBox
        return RimCalibration(
            center: NormalizedPoint(x: box.midX, y: box.midY),
            widthFraction: box.width
        )
    }
}
