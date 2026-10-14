import Foundation

extension KeyboardLayout {
    /// This layout, imported from Oryx as a newer revision of `previous`, with each layer Oryx says it came from keeping
    /// that layer's id (ADR 0054).
    ///
    /// Oryx gives every layer a new `hashId` in each revision and names the one before as `prevHashId`. Sextant keys
    /// durable data by ``Layer/id`` (App Layers rules, Heatmap counts) and matches revisions by it (History), so an
    /// imported layer whose `hashId` or `prevHashId` is what Oryx last called one of `previous`'s layers takes that
    /// layer's id, and remembers Oryx's in ``Layer/oryxID``. A layer with no such match (new in Oryx, or Oryx gave no
    /// `prevHashId`) keeps Oryx's id: nothing is matched by position, since a layer moved or added in Oryx would then take
    /// another layer's rules and counts. Each layer of `previous` is taken once, and `prevHashId` is cleared, used.
    public func keepingLayerIDs(of previous: KeyboardLayout) -> KeyboardLayout {
        var byOryxID: [String: String] = [:]
        for layer in previous.layers where byOryxID[layer.oryxCurrentID] == nil { byOryxID[layer.oryxCurrentID] = layer.id }
        var taken: Set<String> = []
        var next = self
        for index in next.layers.indices {
            let oryxID = next.layers[index].oryxCurrentID
            let match = [oryxID, next.layers[index].oryxPreviousID].lazy.compactMap { $0.flatMap { byOryxID[$0] } }
                .first { !taken.contains($0) }
            let id = match ?? oryxID
            taken.insert(id)
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
