import SwiftUI
import UIKit

// MARK: - Avatar cropper (OM, 2026-10-14)

/// A picked photo waiting for the cropper.
struct WyrmPickedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

extension UIImage {
    /// Drawn upright (camera EXIF turns applied) at scale 1, at most [longest] px.
    func wyrmUpright(longest: CGFloat = 2048) -> UIImage {
        let side = max(size.width, size.height)
        let k = side > longest ? longest / side : 1
        let target = CGSize(width: max(1, (size.width * k).rounded()), height: max(1, (size.height * k).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// Picker, then the cropper, then the 256 px JPEG to upload: one modifier for
/// every place that sets a profile photo.
struct WyrmAvatarPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onJPEG: (Data) -> Void
    @State private var picked: WyrmPickedPhoto?
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                WyrmPhotoPicker { image in
                    isPresented = false
                    guard let image else { return }
                    let upright = image.wyrmUpright()
                    // Let the picker sheet finish closing before the cropper comes up.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { picked = WyrmPickedPhoto(image: upright) }
                }
            }
            .fullScreenCover(item: $picked) { photo in
                WyrmPhotoCropper(image: photo.image, onCancel: { picked = nil }) { data in
                    picked = nil
                    onJPEG(data)
                }
            }
    }
}

extension View {
    func wyrmAvatarPicker(isPresented: Binding<Bool>, onJPEG: @escaping (Data) -> Void) -> some View {
        modifier(WyrmAvatarPickerModifier(isPresented: isPresented, onJPEG: onJPEG))
    }
}

/// Choosing which square of a photo becomes the face, like every other app
/// (OM, 2026-10-14; Android's PhotoCropScreen): the whole photo is on screen,
/// the avatar's squircle sits in the middle with the rest dimmed, and the
/// photo moves under it in any direction and zooms with a pinch. The window
/// is always full. What is framed is exactly what is sent (256 px JPEG).
struct WyrmPhotoCropper: View {
    let image: UIImage
    let onCancel: () -> Void
    let onUse: (Data) -> Void
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var window: CGFloat = 0

    private static let output: CGFloat = 256

    private var cover: CGFloat {
        guard window > 0, image.size.width > 0, image.size.height > 0 else { return 1 }
        return max(window / image.size.width, window / image.size.height)
    }

    private func clamp(_ candidate: CGSize, _ zoom: CGFloat) -> CGSize {
        let drawn = cover * zoom
        let slackX = max(0, (image.size.width * drawn - window) / 2)
        let slackY = max(0, (image.size.height * drawn - window) / 2)
        return CGSize(width: min(max(candidate.width, -slackX), slackX), height: min(max(candidate.height, -slackY), slackY))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button("Cancel", action: onCancel).font(.androidWyrm(16)).foregroundColor(ATheme.link)
                    Spacer()
                }
                Text("Crop photo").font(.androidWyrm(16, .semibold)).foregroundColor(ATheme.ink)
            }.frame(height: 52).padding(.horizontal, 20)
            Rectangle().fill(ATheme.rule).frame(height: 1)
            GeometryReader { geo in
                stage(geo.size)
            }
            Text("Drag the photo to any side and pinch to zoom. What is inside the frame is what everyone sees.")
                .font(.androidWyrm(12)).foregroundColor(ATheme.quiet).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 14)
            HStack(spacing: 10) {
                WSOutlineButton(label: "Cancel", onClick: onCancel).frame(maxWidth: .infinity)
                WSPrimaryButton(label: "Use photo", enabled: window > 0) {
                    if let data = render() { onUse(data) }
                }.frame(maxWidth: .infinity).layoutPriority(1)
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 18)
        }
        .background(ATheme.paper.ignoresSafeArea())
    }

    private func stage(_ area: CGSize) -> some View {
        let side = min(area.width, area.height) * 0.86
        let drawn = cover * scale
        let hole = CGRect(x: (area.width - side) / 2, y: (area.height - side) / 2, width: side, height: side)
        return ZStack {
            Image(uiImage: image).resizable()
                .frame(width: image.size.width * drawn, height: image.size.height * drawn)
                .offset(offset)
            Path { p in
                p.addRect(CGRect(origin: .zero, size: area))
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: side * 0.3, height: side * 0.3), style: .continuous)
            }
            .fill(ATheme.paper.opacity(0.72), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                .stroke(ATheme.ink.opacity(0.85), lineWidth: 2)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
        }
        .frame(width: area.width, height: area.height)
        .background(ATheme.card)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture().onChanged { v in
                    offset = clamp(CGSize(width: baseOffset.width + v.translation.width,
                                          height: baseOffset.height + v.translation.height), scale)
                }.onEnded { _ in baseOffset = offset },
                MagnificationGesture().onChanged { value in
                    scale = min(max(baseScale * value, 1), 6)
                    offset = clamp(offset, scale)
                }.onEnded { _ in baseScale = scale; baseOffset = offset }
            )
        )
        .onAppear { window = side }
        .onChange(of: side) { next in window = next; offset = clamp(offset, scale); baseOffset = offset }
    }

    /// The framed square at upload size: the same transform as the preview.
    private func render() -> Data? {
        guard window > 0 else { return nil }
        let size = Self.output
        let ratio = size / window
        let drawn = cover * scale
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let picture = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let w = image.size.width * drawn * ratio
            let h = image.size.height * drawn * ratio
            let cx = size / 2 + offset.width * ratio
            let cy = size / 2 + offset.height * ratio
            image.draw(in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
        }
        return picture.jpegData(compressionQuality: 0.85)
    }
}
