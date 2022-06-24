//
//  ContentView.swift
//  EmojiArt
//
//  Created by Sebastian Pfeufer on 30.05.22.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    
    let defaultEmojiFontSize: CGFloat = 40
    
    var body: some View {
        VStack(spacing: 0) {
            documentBody
            palette
        }
    }
    
    var documentBody: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                .overlay(
                    OptionalImage(uiImage: document.backgroundImage)
                        .scaleEffect(zoomScale)
                        .position(convertFromEmojiCoordinates((0,0), in: geometry))
                )
                .gesture(doubleTapToZoom(in: geometry.size).exclusively(before: tapToDeselectAllEmojis()))
                if document.backgroundImageFetchStatus == .fetching {
                    ProgressView().scaleEffect(2)
                } else {
                    ForEach(document.emojis) { emoji in
                        Text(emoji.text)
                        .font(animatableWithSize: self.scale(for: emoji))
                        .border(Color.blue, width: selectedEmojis.contains(emoji) ? 2 / zoomScale : 0)
                        .scaleEffect(zoomScale)
                        .position(position(for: emoji, in: geometry))
                        .gesture(selectionGesture(on: emoji).simultaneously(with: longPressToDelete(on: emoji).simultaneously(with: selectedEmojis.contains(emoji) ? panEmojiGesture() : nil)))
                    }
                }
            }
            .clipped()
            .onDrop(of: [.plainText, .url, .image], isTargeted: nil) { providers, location in
                drop(providers: providers, at: location, in: geometry)
            }
            .gesture(panGesture().simultaneously(with: zoomGesture()))
        }
    }
    
    // MARK: - Drag and Drop
    
    private func drop(providers: [NSItemProvider], at location: CGPoint, in geometry: GeometryProxy) -> Bool {
        var found = providers.loadObjects(ofType: URL.self) { url in
            document.setBackground(.url(url.imageURL))
        }
        if !found {
            found = providers.loadObjects(ofType: UIImage.self) { image in
                if let data = image.jpegData(compressionQuality: 1.0) {
                    document.setBackground(.imageData(data))
                }
            }
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                if let emoji = string.first, emoji.isEmoji {
                    document.addEmoji(
                        String(emoji),
                        at: convertToEmojiCoordinates(location, in: geometry),
                        size: defaultEmojiFontSize / zoomScale
                    )
                }
            }
        }
        return found
    }
    
    // MARK: - Positioning/Sizing Emoji
    
    private func position(for emoji: EmojiArtModel.Emoji, in geometry: GeometryProxy) -> CGPoint {
        if selectedEmojis.contains(emoji) {
            return convertFromEmojiCoordinates((emoji.x + Int(gestureEmojiPanOffset.width), emoji.y + Int(gestureEmojiPanOffset.height)), in: geometry)
        } else {
            return convertFromEmojiCoordinates((emoji.x, emoji.y), in: geometry)
        }
    }
    
    private func fontSize(for emoji: EmojiArtModel.Emoji) -> CGFloat {
        CGFloat(emoji.size)
    }
    
    private func convertToEmojiCoordinates(_ location: CGPoint, in geometry: GeometryProxy) -> (x: Int, y: Int) {
        let center = geometry.frame(in: .local).center
        let location = CGPoint(
            x: (location.x - panOffset.width - center.x) / zoomScale,
            y: (location.y - panOffset.height - center.y) / zoomScale
        )
        return (Int(location.x), Int(location.y))
    }
    
    private func convertFromEmojiCoordinates(_ location: (x: Int, y: Int), in geometry: GeometryProxy) -> CGPoint {
        let center = geometry.frame(in: .local).center
        return CGPoint(
            x: center.x + CGFloat(location.x) * zoomScale + panOffset.width,
            y: center.y + CGFloat(location.y) * zoomScale + panOffset.height
        )
    }
    
    // MARK: - Zooming
    
    @State private var steadyStateZoomScale: CGFloat = 1
    @GestureState private var gestureZoomScale: CGFloat = 1
    @GestureState private var gestureZoomScaleEmoji: CGFloat = 1
    
    private var zoomScale: CGFloat {
        steadyStateZoomScale * gestureZoomScale
    }
    
    private func zoomGesture() -> some Gesture {
        if selectedEmojis.isEmpty {
            return MagnificationGesture()
                .updating($gestureZoomScale) { latestGestureScale, gestureZoomScale, _ in
                    gestureZoomScale = latestGestureScale
                }
                .onEnded { gestureScaleAtEnd in
                    steadyStateZoomScale *= gestureScaleAtEnd
                }
        } else {
            return MagnificationGesture()
                .updating($gestureZoomScaleEmoji) { latestGestureScale, gestureZoomScaleEmoji, _ in
                    gestureZoomScaleEmoji = latestGestureScale
                }
                .onEnded { finalGestureScale in
                    for emoji in selectedEmojis {
                        document.scaleEmoji(emoji, by: finalGestureScale)
                    }
                }
        }
    }
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation {
                    zoomToFit(document.backgroundImage, in: size)
                }
            }
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0  {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            steadyStatePanOffset = .zero
            steadyStateZoomScale = min(hZoom, vZoom)
        }
    }
    
    // MARK: - Panning
    
    @State private var steadyStatePanOffset: CGSize = CGSize.zero
    @GestureState private var gesturePanOffset: CGSize = CGSize.zero
    @GestureState private var gestureEmojiPanOffset: CGSize = CGSize.zero
    
    private var panOffset: CGSize {
        (steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { latestDragGestureValue, gesturePanOffset, _ in
                gesturePanOffset = latestDragGestureValue.translation / zoomScale
            }
            .onEnded { finalDragGestureValue in
                steadyStatePanOffset = steadyStatePanOffset + (finalDragGestureValue.translation / zoomScale)
            }
    }
    
    private func panEmojiGesture() -> some Gesture {
        DragGesture()
            .updating($gestureEmojiPanOffset) { latestDragGestureValue, gestureEmojiPanOffset, _ in
                gestureEmojiPanOffset = latestDragGestureValue.distance / zoomScale
            }
            .onEnded { finalDragGestureValue in
                for emoji in selectedEmojis {
                    document.moveEmoji(emoji, by: finalDragGestureValue.distance / zoomScale)
                }
            }
    }
    
    // MARK: - Selecting/deselecting emojis
    
    @State private var selectedEmojisId = Set<Int>()
    
    private var selectedEmojis: Set<EmojiArtModel.Emoji> {
        var selectedEmojis = Set<EmojiArtModel.Emoji>()
        for id in selectedEmojisId {
            selectedEmojis.insert(document.emojis.first(where: {$0.id == id})!)
        }
        return selectedEmojis
    }
    
    private func selectionGesture(on emoji: EmojiArtModel.Emoji) -> some Gesture {
        TapGesture()
            .onEnded {
                withAnimation {
                    selectedEmojisId.toggleMembership(of: emoji.id)
                }
            }
    }
    
    private func tapToDeselectAllEmojis() -> some Gesture {
        TapGesture()
            .onEnded {
                withAnimation {
                    selectedEmojisId = []
                }
            }
    }
    
    // MARK: - Deleting emojis
    
    private func longPressToDelete(on emoji: EmojiArtModel.Emoji) -> some Gesture {
        LongPressGesture(minimumDuration: 1.2)
            .onEnded { LongPressStateAtEnd in
                if let index = selectedEmojisId.firstIndex(of: emoji.id) {
                    selectedEmojisId.remove(at: index)
                }
                document.removeEmoji(emoji)
            }
    }
    
    // MARK: - Supporting functions
    
    private func scale(for emoji: EmojiArtModel.Emoji) -> CGFloat {
        if selectedEmojis.contains(emoji) {
            return emoji.fontSize * self.zoomScale * self.gestureZoomScaleEmoji
        } else {
            return emoji.fontSize * self.zoomScale
        }
    }

    // MARK: - Palette
    
    var palette: some View {
        ScrollingEmojisView(emojis: testEmojis)
            .font(.system(size: defaultEmojiFontSize))
    }
    
    let testEmojis = "😀😷🦠💉👻👀🐶🌲🌎🌞🔥🍎⚽️🚗🚓🚲🛩🚁🚀🛸🏠⌚️🎁🗝🔐❤️⛔️❌❓✅⚠️🎶➕➖🏳️"
}

struct ScrollingEmojisView: View {
    let emojis: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(emojis.map { String($0) }, id: \.self) { emoji in
                    Text(emoji)
                        .onDrag { NSItemProvider(object: emoji as NSString) }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        EmojiArtDocumentView(document: EmojiArtDocument())
    }
}
