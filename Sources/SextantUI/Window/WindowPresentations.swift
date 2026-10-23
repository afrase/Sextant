import SwiftUI

extension View {
    /// The window's sheets, alerts and popovers, one modifier each.
    func windowPresentations(_ model: LayoutWindowModel) -> some View {
        modifier(DeleteLayerAlert(model: model))
            .modifier(LayerPresentations(model: model))
            .modifier(ImportSheetPresenter(model: model))
            .modifier(SaveRevisionSheetPresenter(model: model))
            .modifier(RenameLayoutAlert(model: model))
            .modifier(DeviceWiring(model: model))
            .modifier(ExportPresenter(model: model))
    }
}

/// Confirms deleting a layer that keys still switch to (spec §6.1).
private struct DeleteLayerAlert: ViewModifier {
    var model: LayoutWindowModel

    func body(content: Content) -> some View {
        content.alert(
            Text("Delete this layer?"),
            isPresented: Binding(get: { model.layers.pendingDeletion != nil }, set: { _ in model.layers.pendingDeletion = nil }),
            presenting: model.layers.pendingDeletion
        ) { layer in
            Button("Delete and Clear References", role: .destructive) { model.session?.deleteLayer(layer) }
            Button("Cancel", role: .cancel) {}
        } message: { layer in
            Text(model.deletionMessage(for: layer))
        }
    }
}
