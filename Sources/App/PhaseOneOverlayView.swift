import SwiftUI

private enum WyrmPalette {
    static let paper = Color(red: 0.957, green: 0.937, blue: 0.886)
    static let ink = Color(red: 0.075, green: 0.082, blue: 0.075)
    static let moss = Color(red: 0.396, green: 0.776, blue: 0.545)
    static let fault = Color(red: 0.854, green: 0.272, blue: 0.214)
}

struct PhaseOneOverlayView: View {
    @ObservedObject var status: EngineStatusModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.42), .clear, .black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                Spacer()
                diagnosticCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
        }
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86).delay(0.08)) {
                    revealed = true
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            Image("WyrmMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("WYRM / APPLE LAB")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.35)
                Text("Phase 2 · GPU resource bring-up")
                    .font(.custom("Manrope", size: 13).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .shadow(color: statusColor.opacity(0.65), radius: 7)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.top, 48)
    }

    private var diagnosticCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(statusTitle)
                    .font(.custom("Manrope", size: 21).weight(.bold))
                    .foregroundStyle(WyrmPalette.ink)
                Spacer()
                Text("0.2.0 · 14")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(WyrmPalette.ink.opacity(0.47))
            }

            Text(status.detail)
                .font(.custom("Manrope", size: 13.5).weight(.medium))
                .foregroundStyle(WyrmPalette.ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(WyrmPalette.ink.opacity(0.12))

            HStack(spacing: 0) {
                diagnostic(label: "SHELL", value: "UIKit + SwiftUI")
                Rectangle().fill(WyrmPalette.ink.opacity(0.1)).frame(width: 1, height: 32)
                diagnostic(label: "WINDOW", value: "SDL3")
                Rectangle().fill(WyrmPalette.ink.opacity(0.1)).frame(width: 1, height: 32)
                diagnostic(label: "GPU", value: "Vulkan → Metal")
            }
        }
        .padding(18)
        .background(WyrmPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.38), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: 9)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wyrm Phase 2 engine status. \(statusTitle). \(status.detail)")
    }

    private func diagnostic(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(WyrmPalette.ink.opacity(0.42))
            Text(value)
                .font(.custom("Manrope", size: 10.5).weight(.bold))
                .foregroundStyle(WyrmPalette.ink.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var statusTitle: String {
        switch status.state {
        case .preparing: return "Waking the engine"
        case .ready: return "Atlas uploaded to GPU"
        case .failed: return "Engine needs attention"
        }
    }

    private var statusColor: Color {
        switch status.state {
        case .preparing: return .yellow
        case .ready: return WyrmPalette.moss
        case .failed: return WyrmPalette.fault
        }
    }
}
