import Observation
import SwiftUI

@MainActor @Observable
final class BuildSDKProbeModel {
    var value = 0
}

@MainActor
struct BuildSDKProbeView: View {
    @Bindable var model: BuildSDKProbeModel
    @State private var selection = 0
    var body: some View { Text("\(model.value + selection)") }
}
