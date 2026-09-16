import SwiftUI

private enum WyrmPalette {
    static let paper = Color(red: 0.965, green: 0.949, blue: 0.909)
    static let ink = Color(red: 0.071, green: 0.082, blue: 0.071)
    static let moss = Color(red: 0.35, green: 0.76, blue: 0.51)
    static let red = Color(red: 0.85, green: 0.22, blue: 0.20)
}

struct PhaseOneOverlayView: View {
    @ObservedObject var status: EngineStatusModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.40), .clear, .black.opacity(0.40)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer()
                bottomSurface
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
        }
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion { revealed = true }
            else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86).delay(0.08)) {
                    revealed = true
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image("WyrmMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text("WYRM / FIELD TEST")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.25)
                Text("Offline · native C + Vulkan")
                    .font(.custom("Manrope", size: 12).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))
            }
            Spacer()
            Circle()
                .fill(status.state == .failed ? WyrmPalette.red : WyrmPalette.moss)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.top, 48)
    }

    @ViewBuilder private var bottomSurface: some View {
        if status.state == .failed {
            paperSurface {
                VStack(alignment: .leading, spacing: 12) {
                    titleRow("Engine needs attention")
                    Text(status.detail)
                        .font(.custom("Manrope", size: 13))
                        .foregroundStyle(WyrmPalette.ink.opacity(0.7))
                }
            }
        } else if status.state == .preparing {
            paperSurface {
                VStack(alignment: .leading, spacing: 12) {
                    titleRow("Waking the engine")
                    Text("Preparing the Wyrm atlas and Apple GPU.")
                        .font(.custom("Manrope", size: 13))
                }
            }
        } else {
            switch status.gameMode {
            case .menu: menuSurface
            case .playing: playingSurface
            case .paused: pausedSurface
            case .ended: endedSurface
            }
        }
    }

    private var menuSurface: some View {
        paperSurface {
            VStack(alignment: .leading, spacing: 14) {
                eyebrow("FIELD NOTES / 01")
                titleRow("A little room to roam.")
                Text("Guide your Wyrm with your finger. Eat the green beads, grow, and stay inside the field.")
                    .font(.custom("Manrope", size: 13.5).weight(.medium))
                    .foregroundStyle(WyrmPalette.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                action("PLAY OFFLINE", icon: "arrow.up.right", action: { status.onStart?() })
                Text("Local prototype · no sign-in or network")
                    .font(.custom("Manrope", size: 10.5))
                    .foregroundStyle(WyrmPalette.ink.opacity(0.50))
            }
        }
    }

    private var playingSurface: some View {
        paperSurface {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    eyebrow("SCORE")
                    Text("\(status.score)")
                        .font(.custom("Manrope", size: 30).weight(.heavy))
                        .monospacedDigit()
                }
                Spacer()
                Text("DRAG TO STEER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(WyrmPalette.ink.opacity(0.52))
                Button("PAUSE") { status.onPause?() }
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .background(WyrmPalette.ink)
                    .foregroundStyle(WyrmPalette.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .buttonStyle(.plain)
            }
        }
    }

    private var pausedSurface: some View {
        paperSurface {
            VStack(alignment: .leading, spacing: 13) {
                eyebrow("FIELD NOTES / PAUSED")
                titleRow("Take a breath.")
                Text("Score \(status.score) · Your run is waiting.")
                    .font(.custom("Manrope", size: 13))
                action("RESUME", icon: "arrow.right", action: { status.onResume?() })
            }
        }
    }

    private var endedSurface: some View {
        paperSurface {
            VStack(alignment: .leading, spacing: 13) {
                eyebrow("FIELD NOTES / RUN ENDED")
                titleRow("One more turn?")
                Text("You collected \(status.score) green \(status.score == 1 ? "bead" : "beads").")
                    .font(.custom("Manrope", size: 13))
                action("PLAY AGAIN", icon: "arrow.clockwise", action: { status.onStart?() })
            }
        }
    }

    private func paperSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .foregroundStyle(WyrmPalette.ink)
            .background(WyrmPalette.paper)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 22, y: 9)
            .padding(.bottom, 22)
    }

    private func eyebrow(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .tracking(1.15)
            .foregroundStyle(WyrmPalette.ink.opacity(0.52))
    }

    private func titleRow(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(value)
                .font(.custom("Manrope", size: 22).weight(.heavy))
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text("0.3.0 · 18")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(WyrmPalette.ink.opacity(0.45))
        }
    }

    private func action(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).tracking(1.1)
                Spacer()
                Image(systemName: icon)
            }
            .font(.system(size: 12, weight: .heavy, design: .monospaced))
            .padding(.horizontal, 17)
            .frame(minHeight: 50)
            .foregroundStyle(WyrmPalette.paper)
            .background(WyrmPalette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
