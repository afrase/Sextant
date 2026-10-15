import Foundation

extension KeyboardLayout {
    /// This layout, imported from Oryx as a newer revision of `previous`, with each layer Oryx says it came from keeping
    /// that layer's id (ADR 0054).
    ///
    /// Oryx gives every layer a new `hashId` in each revision and names the one before as `prevHashId`. Sextant keys
    /// durable data by ``Layer/id`` (App Layers rules, Heatmap counts) and matches revisions by it (History), so an
    /// imported layer whose `hashId` or `prevHashId` is what Oryx last called one of `previous`'s layers takes that
    /// layer's id, and remembers Oryx's in ``Layer/oryxID``. When an Oryx revision was skipped between imports, a layer's
    /// `prevHashId` names one Sextant never saw: it then takes the one unmatched earlier layer with its title, if the title
    /// is unique on both sides. Any other layer (new in Oryx, or Oryx gave no `prevHashId`) keeps Oryx's id: nothing is
    /// matched by position, since a layer moved or added in Oryx would then take another layer's rules and counts. Each
    /// layer of `previous` is taken once, and `prevHashId` is cleared, used.
    public func keepingLayerIDs(of previous: KeyboardLayout) -> KeyboardLayout {
        var byOryxID: [String: String] = [:]
        for layer in previous.layers where byOryxID[layer.oryxCurrentID] == nil { byOryxID[layer.oryxCurrentID] = layer.id }
        var taken: Set<String> = []
        var next = self
        var matches = next.layers.map { layer in
            [layer.oryxCurrentID, layer.oryxPreviousID].lazy.compactMap { $0.flatMap { byOryxID[$0] } }.first
        }
        for index in matches.indices {
            if let match = matches[index], !taken.insert(match).inserted { matches[index] = nil }
        }
        // A layer that names an earlier one Sextant never saw (an Oryx revision skipped between imports) takes the one
        // earlier layer of the same title, when both titles are unique: a title only, never a position.
        func unique(_ titles: [String]) -> Set<String> {
            Set(Dictionary(grouping: titles, by: { $0 }).filter { $0.value.count == 1 }.keys)
        }
        let open = previous.layers.filter { !taken.contains($0.id) }
        let openTitles = unique(open.map(\.title))
        let lost = next.layers.indices.filter { matches[$0] == nil && next.layers[$0].oryxPreviousID != nil }
        let lostTitles = unique(lost.map { next.layers[$0].title })
        for index in lost where openTitles.contains(next.layers[index].title) && lostTitles.contains(next.layers[index].title) {
            matches[index] = open.first { $0.title == next.layers[index].title }?.id
        }
        for index in next.layers.indices {
            let oryxID = next.layers[index].oryxCurrentID
            let id = matches[index] ?? oryxID
            next.layers[index].id = id
            next.layers[index].oryxID = id == oryxID ? nil : oryxID
            next.layers[index].oryxPreviousID = nil
        }
        // An unmatched layer whose Oryx id is one a matched layer kept: give it an id of its own.
        var seen: Set<String> = []
        for index in next.layers.indices where !seen.insert(next.layers[index].id).inserted {
            next.layers[index].oryxID = next.layers[index].oryxCurrentID
            next.layers[index].id = UUID().uuidString
        }
        return next
    }
}
