import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: Double] = Dictionary(
        uniqueKeysWithValues: Tuning.items.map { ($0.id, Tuning.value($0.id)) }
    )

    private func binding(for item: Tuning.Item) -> Binding<Double> {
        Binding(
            get: { values[item.id] ?? item.defaultValue },
            set: { newValue in
                values[item.id] = newValue
                Tuning.set(newValue, for: item.id)
            }
        )
    }

    private func format(_ item: Tuning.Item, _ value: Double) -> String {
        let text = item.step >= 1 ? String(format: "%.0f", value)
            : (item.step < 0.01 ? String(format: "%.3f", value) : String(format: "%.2f", value))
        return text + item.unit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("카메라 화면은 열 때마다 이 값을 새로 읽어요. 코트에서 바꾼 뒤 실시간 카메라를 다시 열면 적용돼요.")
                        .font(.footnote)
                        .foregroundStyle(HUD.dim)
                }

                ForEach(Tuning.items) { item in
                    Section {
                        if item.kind == .toggle {
                            Toggle(item.title, isOn: Binding(
                                get: { (values[item.id] ?? 0) >= 0.5 },
                                set: { binding(for: item).wrappedValue = $0 ? 1 : 0 }
                            ))
                        } else {
                            HStack {
                                Text(item.title).font(HUD.font(16))
                                Spacer()
                                Text(format(item, values[item.id] ?? item.defaultValue))
                                    .font(HUD.font(16).monospacedDigit())
                                    .foregroundStyle(HUD.orange)
                            }
                            Slider(value: binding(for: item), in: item.range, step: item.step)
                        }
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(HUD.dim)
                    }
                }

                Section {
                    Button("모두 기본값으로 되돌리기", role: .destructive) {
                        Tuning.reset()
                        for item in Tuning.items { values[item.id] = item.defaultValue }
                    }
                }

                Section("코트에서 확인할 것") {
                    checklist("림을 탭해서 '림 인식'이 ✅가 되는지")
                    checklist("림이 점선 박스 안에 오면 '림 위치'가 ✅가 되는지")
                    checklist("가이드 안내 방향('폰을 왼쪽으로…')이 실제로 맞는지")
                    checklist("백보드 위·아래를 찍고 '림·백보드 크기 일치'가 ✅가 되는지")
                    checklist("폰을 2~3° 기울여 찍어 보정 켠 쪽이 평균 각도 차이가 더 작은지 (아니면 롤 뒤집기)")
                    checklist("아무것도 안 던질 때 노란(주황) 선이 안 뜨는지")
                    checklist("공을 던지면 선이 따라가고 입사각이 뜨는지")
                }
            }
            .scrollContentBackground(.hidden)
            .background(HUD.background.ignoresSafeArea())
            .navigationTitle("튜닝 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(HUD.orange)
    }

    private func checklist(_ text: String) -> some View {
        Label(text, systemImage: "square")
            .font(.footnote)
    }
}
