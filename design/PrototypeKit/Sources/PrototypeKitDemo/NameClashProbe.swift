// Compile-time probe: every public PrototypeKit type, named unqualified in a file that also imports
// SwiftUI, AppKit, Foundation, Observation and UniformTypeIdentifiers. If a future SDK adds a clashing
// name, this file stops compiling.
import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import PrototypeKit

let prototypeKitPublicTypes: [Any.Type] = [
    HexColor.self, Modifiers.self, MacroStep.self, Macro.self, KeyAction.self, KeySlot.self, KeyKind.self, Key.self,
    Layer.self, Combo.self, NavigatorConfig.self, KeyboardLayout.self, ResolvedKey.self, KeyChange.self, LayerRename.self,
    LayoutDiff.self, OryxDecodingError.self, SettingValue.self, Setting.self, SettingsSection.self, SettingsCatalog.self,
    KeycodeCategory.self, ModifierSide.self, KeycodeEntry.self, KeycodeCatalog.self, ActionLegend.self, KeyLegend.self,
    ResolvedLegend.self, Legends.self, BoardGeometry.self, BoardLayout.self, BoardCanvas<EmptyView>.self,
    FittedBoardCanvas<EmptyView>.self, Samples.self, AppLayerRule.self, KeyHeatmap.self, LiveEvent.self, LiveScript.self,
    MockDevice.self, LayoutRevision.self, RevisionHistory.self, KeyRef.self, FirmwareImage.self, FirmwareSizeMeter.self,
    BuildLogLine.self, BuildFailure.self, BuildFlashPhase.self, BuildFlashSimulator.self, OryxLayoutReference.self,
    OryxImportPreview.self, EditorSelection.self, EditorStore.self, SnapshotAppearance.self, SnapshotScene.self,
    SnapshotOverlay.self, SnapshotRunner.self, PrototypeKit.self, PrototypeResources.self,
]
