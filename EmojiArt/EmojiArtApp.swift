//
//  EmojiArtApp.swift
//  EmojiArt
//
//  Created by Sebastian Pfeufer on 30.05.22.
//

import SwiftUI

@main
struct EmojiArtApp: App {
    let document = EmojiArtDocument()
    
    var body: some Scene {
        WindowGroup {
            EmojiArtDocumentView(document: document)
        }
    }
}
