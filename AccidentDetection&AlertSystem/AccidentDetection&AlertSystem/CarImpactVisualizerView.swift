import SwiftUI

// MARK: - Impact Zones
enum CarImpactZone: String {
    case none       = "Safe"
    case front      = "Front"
    case frontLeft  = "Front-Left"
    case frontRight = "Front-Right"
    case left       = "Left Side"
    case right      = "Right Side"
    case rear       = "Rear"
    case rearLeft   = "Rear-Left"
    case rearRight  = "Rear-Right"
    case rollover   = "Rollover / Roof"
}

// MARK: - Helper Functions (Frontend)

/// 1. Resolves the correct car wireframe asset name from user make and category
func getCarImageName(make: String, categoryId: Int) -> String {
    let lower = make.lowercased()
    if lower.contains("suv") || categoryId == 1 && !lower.contains("sedan") && !lower.contains("hatchback") {
        return "suv"
    } else if lower.contains("hatchback") || categoryId == 2 {
        return "hatchback"
    } else if lower.contains("sedan") || categoryId == 3 {
        return "sedan"
    }
    return "sedan" // Default fallback
}

/// 2. Resolves exact proportional aspect ratio (width / height)
func getCarAspectRatio(imageName: String) -> CGFloat {
    switch imageName {
    case "suv":
        return 624.0 / 1024.0   // ~0.61
    case "hatchback":
        return 878.0 / 1024.0   // ~0.86
    default:
        return 948.0 / 1659.0   // ~0.57 (sedan)
    }
}

/// 3. Parses the backend impact side string into a typed CarImpactZone
func detectImpactZone(impactSide: String, isAccident: Bool) -> CarImpactZone {
    guard isAccident else { return .none }
    
    let side = impactSide.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    
    if side.contains("rollover") {
        return .rollover
    } else if side.contains("front") && side.contains("left") {
        return .frontLeft
    } else if side.contains("front") && side.contains("right") {
        return .frontRight
    } else if (side.contains("rear") || side.contains("back")) && side.contains("left") {
        return .rearLeft
    } else if (side.contains("rear") || side.contains("back")) && side.contains("right") {
        return .rearRight
    } else if side.contains("front") {
        return .front
    } else if side.contains("rear") || side.contains("back") {
        return .rear
    } else if side.contains("left") {
        return .left
    } else if side.contains("right") {
        return .right
    }
    
    return .front // Fallback default when accident is active
}

/// 4. Main easy-to-understand frontend function to display the car with highlighted affected area
@ViewBuilder
func makeCarImpactVisualizer(
    make: String,
    plate: String,
    categoryId: Int = 1,
    isAccident: Bool,
    impactSide: String,
    cabinDamage: Double = 0
) -> some View {
    CarImpactVisualizerView(
        make: make,
        plate: plate,
        categoryId: categoryId,
        isAccident: isAccident,
        impactSide: impactSide,
        cabinDamage: cabinDamage
    )
}

// MARK: - Visualizer Component
struct CarImpactVisualizerView: View {
    var make: String
    var plate: String
    var categoryId: Int
    var isAccident: Bool
    var impactSide: String
    var cabinDamage: Double
    
    @State private var pulseAnimation = false
    
    private var imageName: String {
        getCarImageName(make: make, categoryId: categoryId)
    }
    
    private var aspectRatio: CGFloat {
        getCarAspectRatio(imageName: imageName)
    }
    
    private var impactZone: CarImpactZone {
        detectImpactZone(impactSide: impactSide, isAccident: isAccident)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Header: Vehicle info and live status badge
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .foregroundColor(isAccident ? .red : .blue)
                    Text(make.isEmpty ? "Selected Car" : make)
                        .font(.system(size: 15, weight: .bold))
                    if !plate.isEmpty && plate != "-" {
                        Text("(\(plate))")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Status Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(isAccident ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAccident && pulseAnimation ? 1.4 : 1.0)
                    
                    Text(isAccident ? "\(impactZone.rawValue.uppercased()) IMPACT" : "ALL ZONES OK")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isAccident ? .red : .green)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isAccident ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                .cornerRadius(12)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            
            // Car wireframe with affected area highlight
            let displayHeight: CGFloat = 230
            let displayWidth = displayHeight * aspectRatio
            
            ZStack {
                // Background plate for vehicle
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.97))
                    .frame(height: displayHeight + 20)
                
                // Blueprint Car Image
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displayWidth, height: displayHeight)
                    .opacity(isAccident ? 0.9 : 1.0)
                
                // Highlight Overlay for the Affected Area
                if isAccident && impactZone != .none {
                    highlightOverlay(for: impactZone, width: displayWidth, height: displayHeight)
                }
            }
            .frame(height: displayHeight + 20)
            .padding(.horizontal, 10)
            
            // Bottom impact info caption banner
            if isAccident {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Affected Area: \(impactZone.rawValue)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red)
                        Text(cabinDamage > 0 ? String(format: "Structural Damage: %.0f%%", cabinDamage) : "Impact detected on this side")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
    
    // MARK: - Highlight Overlay Builder
    @ViewBuilder
    private func highlightOverlay(for zone: CarImpactZone, width: CGFloat, height: CGFloat) -> some View {
        let coords = getZoneCenter(zone: zone, width: width, height: height)
        
        ZStack {
            // Special case: Rollover affects whole vehicle cabin
            if zone == .rollover {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.red, lineWidth: 4)
                    .background(Color.red.opacity(0.25))
                    .frame(width: width * 0.75, height: height * 0.65)
                    .scaleEffect(pulseAnimation ? 1.05 : 0.95)
                
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.red)
            } else {
                // Expanding ripple 1
                Circle()
                    .fill(Color.red.opacity(pulseAnimation ? 0.35 : 0.15))
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulseAnimation ? 1.25 : 0.85)
                    .position(x: coords.x, y: coords.y)
                
                // Expanding ripple 2
                Circle()
                    .stroke(Color.red.opacity(0.8), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulseAnimation ? 1.15 : 0.9)
                    .position(x: coords.x, y: coords.y)
                
                // Core impact epicenter
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [Color.yellow, Color.red]),
                        center: .center,
                        startRadius: 2,
                        endRadius: 14
                    ))
                    .frame(width: 26, height: 26)
                    .shadow(color: .red, radius: 8)
                    .position(x: coords.x, y: coords.y)
                
                // Flash indicator icon
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .position(x: coords.x, y: coords.y)
            }
        }
        .frame(width: width, height: height)
    }
    
    // MARK: - Coordinates for each zone
    private func getZoneCenter(zone: CarImpactZone, width: CGFloat, height: CGFloat) -> CGPoint {
        switch zone {
        case .front:
            return CGPoint(x: width * 0.50, y: height * 0.08)
        case .frontLeft:
            return CGPoint(x: width * 0.22, y: height * 0.10)
        case .frontRight:
            return CGPoint(x: width * 0.78, y: height * 0.10)
        case .left:
            return CGPoint(x: width * 0.15, y: height * 0.50)
        case .right:
            return CGPoint(x: width * 0.85, y: height * 0.50)
        case .rear:
            return CGPoint(x: width * 0.50, y: height * 0.92)
        case .rearLeft:
            return CGPoint(x: width * 0.22, y: height * 0.90)
        case .rearRight:
            return CGPoint(x: width * 0.78, y: height * 0.90)
        case .rollover, .none:
            return CGPoint(x: width * 0.50, y: height * 0.50)
        }
    }
}
