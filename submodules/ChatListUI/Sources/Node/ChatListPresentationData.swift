import Foundation
import UIKit
import TelegramPresentationData
import TelegramUIPreferences
import ChatListTitleView // MEDIATOK: chat list row style (MTChatListStyleHooks)

public final class ChatListPresentationData {
    public let theme: PresentationTheme
    public let fontSize: PresentationFontSize
    public let strings: PresentationStrings
    public let dateTimeFormat: PresentationDateTimeFormat
    public let nameSortOrder: PresentationPersonNameOrder
    public let nameDisplayOrder: PresentationPersonNameOrder
    public let disableAnimations: Bool
    // MEDIATOK: the look of the rows, taken once per presentation data (MTChatListStyleHooks.rowStyle)
    public let mtRowStyle: MTChatListRowStyle
    
    public init(theme: PresentationTheme, fontSize: PresentationFontSize, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, nameSortOrder: PresentationPersonNameOrder, nameDisplayOrder: PresentationPersonNameOrder, disableAnimations: Bool) {
        self.theme = theme
        self.fontSize = fontSize
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        self.nameSortOrder = nameSortOrder
        self.nameDisplayOrder = nameDisplayOrder
        self.disableAnimations = disableAnimations
        self.mtRowStyle = mtChatListRowStyle() // MEDIATOK: see the property
    }
}
