import Foundation
import MTAppearanceSettings

/// Entry point of the MTAppearance feature module (owner MediaTok): appearance of messages, theme and
/// backgrounds, the profile's info rows and header.
///
/// One snapshot (`MTAppearanceSnapshot`) carries everything that changes the theme or the layout of
/// messages; it rebuilds the theme once per change (MTThemeHooks.invalidate). Decorations that need
/// no relayout (animated backgrounds, snowfall, screen-edge bands) follow their own settings' signals.
public enum MTAppearanceModule {
    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `MTFeatures.registerAll()`, before `MTHookRegistry.freeze()`.
    public static func register() {
        assert(Thread.isMainThread)
        MTAppearanceSettings.declare()
        MTAppearanceMigration.register()
        MTMediaTokWave7Tools.register()

        MTFonts.register()
        MTChatTextFonts.register()
        MTMediaTokLangs.register()
        MTMediaTokColorSticker.register()
        MTMediaTokCalculator.register()
        MTMediaTokE2E.register()
        MTMediaTokDiscordProfile.register()
        MTMediaTokAudioGuard.register()
        MTMediaTokWave4Tools.register()
        MTMediaTokStickerVault.register()
        MTMediaTokWave5Tools.register()
        MTMediaTokLiquidUI.register()
        MTMediaTokWave6Tools.register()
        MTMediaTokWave8Tools.register()
        MTMediaTokWave9Tools.register()
        MTMediaTokWave10Tools.register()
        MTMediaTokWave11Tools.register()
        MTMediaTokWave12Tools.register()
        MTMediaTokWave13Tools.register()
        MTMediaTokWave14Tools.register()
        MTMediaTokWave15Tools.register()
        MTMediaTokWave16Tools.register()
        MTMediaTokWave17Tools.register()
        MTMediaTokWave18Tools.register()
        MTCustomFonts.registerProvider()
        MTAppearanceTheme.register()
        MTAmoledKeyboard.register()
        MTChatMessages.register()
        MTChatDecor.register()
        MTChatListDecor.register()
        MTProfileDecor.register()
        MTAppearancePendingPoints.register()

        MTAppearanceMenu.register()
    }
}
