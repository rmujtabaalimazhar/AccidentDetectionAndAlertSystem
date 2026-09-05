
import SwiftUI

struct SensorRow: View {
    var label: String
    var x: Double
    var y: Double
    var z: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.gray)
            HStack {
                SensorVal(axis: "X", val: x)
                Spacer()
                SensorVal(axis: "Y", val: y)
                Spacer()
                SensorVal(axis: "Z", val: z)
            }
        }
    }
}

struct SensorVal: View {
    var axis: String
    var val: Double
    var body: some View {
        HStack(spacing: 4) {
            Text(axis).font(.caption2).font(Font.body.weight(.bold)).foregroundColor(.orange)
            Text(String(format: "%.3f", val)).font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }
}

