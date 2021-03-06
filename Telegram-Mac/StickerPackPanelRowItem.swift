//
//  StickerPackPanelRowItem.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 08/07/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit


class StickerPackPanelRowItem: TableRowItem {
    private(set) var files: [(TelegramMediaFile, ChatMediaContentView.Type, NSPoint)] = []
    let packNameLayout: TextViewLayout?
    let context: AccountContext
    let arguments: StickerPanelArguments
    let namePoint: NSPoint
    let packInfo: StickerPackInfo
    let collectionId: StickerPackCollectionId
    let _files:[TelegramMediaFile]
    
    private var _height: CGFloat = 0
    override var stableId: AnyHashable {
        return collectionId
    }
    let packReference: StickerPackReference?
    
    private let preloadFeaturedDisposable = MetaDisposable()
    let canSend: Bool
    let playOnHover: Bool
    init(_ initialSize: NSSize, context: AccountContext, arguments: StickerPanelArguments, files:[TelegramMediaFile], packInfo: StickerPackInfo, collectionId: StickerPackCollectionId, canSend: Bool, playOnHover: Bool = false) {
        self.context = context
        self.arguments = arguments
        self.canSend = canSend
        self._files = files
        self.playOnHover = playOnHover
        
        let title: String?
        var count: Int32 = 0
        switch packInfo {
        case let .pack(info, _, _):
            title = info?.title ?? info?.shortName ?? ""
            count = info?.count ?? 0
            if let info = info {
                self.packReference = .id(id: info.id.id, accessHash: info.accessHash)
            } else {
                self.packReference = nil
            }
        case .recent:
            title = strings().stickersRecent
            self.packReference = nil
        case .saved:
            title = nil
            self.packReference = nil
        case .emojiRelated:
            title = nil
            self.packReference = nil
        case let .speficicPack(info):
            title = info?.title ?? info?.shortName ?? ""
            if let info = info {
                self.packReference = .id(id: info.id.id, accessHash: info.accessHash)
            } else {
                self.packReference = nil
            }
        }
        
        if let title = title {
            let attributed = NSMutableAttributedString()
            if packInfo.featured {
                _ = attributed.append(string: title.uppercased(), color: theme.colors.text, font: .medium(14))
                _ = attributed.append(string: "\n")
                _ = attributed.append(string: strings().stickersCountCountable(Int(count)), color: theme.colors.grayText, font: .normal(12))
            } else {
                _ = attributed.append(string: title.uppercased(), color: theme.colors.grayText, font: .medium(.text))
            }
            let layout = TextViewLayout(attributed, alwaysStaticItems: true)
            layout.measure(width: 300)
            self.packNameLayout = layout
            
            self.namePoint = NSMakePoint(10, floorToScreenPixels(System.backingScale, ((packInfo.featured ? 50 : 30) - layout.layoutSize.height) / 2))
        } else {
            namePoint = NSZeroPoint
            self.packNameLayout = nil
        }
        
        self.packInfo = packInfo
        self.collectionId = collectionId
        
        
       
        
        if packInfo.featured, let id = collectionId.itemCollectionId {
            preloadFeaturedDisposable.set(preloadedFeaturedStickerSet(network: context.account.network, postbox: context.account.postbox, id: id).start())
        }
        
        super.init(initialSize)
        
        _ = makeSize(initialSize.width, oldWidth: 0)
        
    }
    
    override func makeSize(_ width: CGFloat = CGFloat.greatestFiniteMagnitude, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        var filesAndPoints:[(TelegramMediaFile, ChatMediaContentView.Type, NSPoint)] = []

        
        let size: NSSize = NSMakeSize(60, 60)

        var point: NSPoint = NSMakePoint(5, packNameLayout == nil ? 5 : !packInfo.featured ? 35 : 55)
        var rowCount: CGFloat = 1
        var countFixed = false
        for file in _files {
            var filePoint = point
            let fileSize = file.dimensions?.size.aspectFitted(size) ?? size
            filePoint.y += (size.height - fileSize.height) / 2
            filePoint.x += (size.width - fileSize.width) / 2
            filesAndPoints.append((file, ChatLayoutUtils.contentNode(for: file, packs: true), filePoint))

            point.x += size.width + 10
            if point.x + size.width >= width {
                point.y += size.height + 5
                point.x = 5
                countFixed = true
            }
            if !countFixed {
                rowCount += 1
            }
        }
        
        self.files = filesAndPoints

        let rows = ceil((CGFloat(_files.count) / rowCount))
        _height = (packNameLayout == nil ? 0 : !packInfo.featured ? 30 : 50) + 60.0 * rows + ((rows + 1) * 5)

        
        return true
    }
    
    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items:[ContextMenuItem] = []
        let context = self.context
        if arguments.mode != .common {
            return .single([])
        }
        for file in files {
            let rect = NSMakeRect(file.2.x, file.2.y, 60, 60)
            let file = file.0
            if NSPointInRect(location, rect) {
                
                if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
                    if file.isAnimatedSticker, let data = try? Data(contentsOf: URL(fileURLWithPath: context.account.postbox.mediaBox.resourcePath(file.resource))) {
                        items.append(ContextMenuItem("Copy thumbnail (Dev.)", handler: {
                        _ = getAnimatedStickerThumb(data: data).start(next: { path in
                                if let path = path {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.writeObjects([NSURL(fileURLWithPath: path)])
                                }
                            })
                        }, itemImage: MenuAnimation.menu_copy_media.value))
                    }
                }
                
                inner: switch packInfo {
                case .saved, .recent:
                    if let reference = file.stickerReference {
                        items.append(ContextMenuItem(strings().contextViewStickerSet, handler: { [weak self] in
                            self?.arguments.showPack(reference)
                        }, itemImage: MenuAnimation.menu_view_sticker_set.value))
                    }
                default:
                    break inner
                }
                inner: switch packInfo {
                case .saved:
                    if let mediaId = file.id {
                        items.append(ContextMenuItem(strings().contextRemoveFaveSticker, handler: {
                            _ = removeSavedSticker(postbox: context.account.postbox, mediaId: mediaId).start()
                        }, itemImage: MenuAnimation.menu_remove_from_favorites.value))
                    }
                default:
                    if packInfo.installed {
                        items.append(ContextMenuItem(strings().chatContextAddFavoriteSticker, handler: {
                            _ = addSavedSticker(postbox: context.account.postbox, network: context.account.network, file: file).start()
                        }, itemImage: MenuAnimation.menu_add_to_favorites.value))
                    }
                }
                
                if canSend {
                    items.append(ContextMenuItem(strings().chatSendWithoutSound, handler: { [weak self] in
                        guard let `self` = self else {
                            return
                        }
                        let contentView = (self.view as? StickerPackPanelRowView)?.subviews.compactMap { $0 as? ChatMediaContentView}.first(where: { view -> Bool in
                            return view.media?.isEqual(to: file) ?? false
                        })
                        
                        if let contentView = contentView {
                            self.arguments.sendMedia(file, contentView, true, false)
                        }
                    }, itemImage: MenuAnimation.menu_mute.value))
                    
                    items.append(ContextMenuItem(strings().chatSendScheduledMessage, handler: { [weak self] in
                        guard let `self` = self else {
                            return
                        }
                        let contentView = (self.view as? StickerPackPanelRowView)?.subviews.compactMap { $0 as? ChatMediaContentView}.first(where: { view -> Bool in
                            return view.media?.isEqual(to: file) ?? false
                        })
                        
                        if let contentView = contentView {
                            self.arguments.sendMedia(file, contentView, false, true)
                        }
                    }, itemImage: MenuAnimation.menu_schedule_message.value))
                }
                break
            }
        }
        
       
        
        return .single(items)
    }
    
    deinit {
        preloadFeaturedDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
    }
    
    override var height: CGFloat {
        return _height
    }
    
    override func viewClass() -> AnyClass {
        return StickerPackPanelRowView.self
    }
}

private final class StickerPackPanelRowView : TableRowView, ModalPreviewRowViewProtocol {
    
    func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        for subview in self.subviews {
            if let contentView = subview as? ChatMediaContentView {
                if NSPointInRect(point, subview.frame) {
                    if let file = contentView.media as? TelegramMediaFile {
                        let reference = file.stickerReference != nil ? FileMediaReference.stickerPack(stickerPack: file.stickerReference!, media: file) : FileMediaReference.standalone(media: file)
                        if file.isVideoSticker && !file.isWebm {
                            return (.file(reference, GifPreviewModalView.self), contentView)
                        } else if file.isAnimatedSticker || file.isWebm {
                            return (.file(reference, AnimatedStickerPreviewModalView.self), contentView)
                        } else if file.isStaticSticker {
                            return (.file(reference, StickerPreviewModalView.self), contentView)
                        }
                    }
                }
            }
            
        }
        return nil
    }
    
    private var contentViews:[Optional<ChatMediaContentView>] = []
    private let packNameView = TextView()
    private var clearRecentButton: ImageButton?
    private var addButton:TitleButton?
    private let longDisposable = MetaDisposable()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(packNameView)
        packNameView.userInteractionEnabled = false
        packNameView.isSelectable = false
        wantsLayer = false
        
    }
    private var isMouseDown: Bool = false
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        longDisposable.set(nil)
        
        self.isMouseDown = true
        
        guard event.clickCount == 1 else {
            return
        }
        
        let point = convert(event.locationInWindow, from: nil)
        for subview in self.subviews {
            if NSPointInRect(point, subview.frame) {
                if subview is ChatMediaContentView {
                    let signal = Signal<Never, NoError>.complete() |> delay(0.2, queue: .mainQueue())
                    longDisposable.set(signal.start(completed: { [weak self] in
                        if let `self` = self, self.mouseInside(),
                            let item = self.item as? StickerPackPanelRowItem,
                            let table = item.table,
                            let window = self.window as? Window {
                            startModalPreviewHandle(table, window: window, context: item.context)
                        }
                    }))
                }
                return
            }
        }
        
    }
    
    override func mouseUp(with event: NSEvent) {
        //super.mouseUp(with: event)
        longDisposable.set(nil)
        if isMouseDown, mouseInside(), event.clickCount == 1 {
            let point = convert(event.locationInWindow, from: nil)
            
            if let item = item as? StickerPackPanelRowItem {
                if self.packNameView.mouseInside() {
                    if let reference = item.packReference {
                        item.arguments.showPack(reference)
                    }
                } else {
                    for subview in self.subviews {
                        if NSPointInRect(point, subview.frame) {
                            if let contentView = subview as? ChatMediaContentView, let media = contentView.media {
                                if let reference = item.packReference, item.packInfo.featured {
                                    item.arguments.showPack(reference)
                                } else {
                                    item.arguments.sendMedia(media, contentView, false, false)
                                }
                            }
                            break
                        }
                    }
                }
            }
        }
        isMouseDown = false
    }
    deinit {
        longDisposable.dispose()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var previousRange: (Int, Int) = (0, 0)
    private var isCleaned: Bool = false
    
    override func layout() {
        super.layout()
        
        guard let item = item as? StickerPackPanelRowItem else {
            return
        }
        packNameView.setFrameOrigin(item.namePoint)
        
        self.clearRecentButton?.setFrameOrigin(frame.width - 34, item.namePoint.y - 10)

        updateVisibleItems()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateVisibleItems()
    }

    override var backdorColor: NSColor {
        return .clear
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateVisibleItems()
    }
    
    @objc func updateVisibleItems() {
        
        guard let item = item as? StickerPackPanelRowItem else {
            return
        }
                
        let size: NSSize = NSMakeSize(60, 60)
        
        let visibleRect = self.visibleRect.insetBy(dx: 0, dy: -120)
        
        if self.visibleRect != NSZeroRect && superview != nil && window != nil {
            let visibleRange = (Int(ceil(visibleRect.minY / (size.height + 10))), Int(ceil(visibleRect.height / (size.height + 10))))
            if visibleRange != self.previousRange {
                self.previousRange = visibleRange
                isCleaned = false
            } else {
                return
            }
        } else {
            self.previousRange = (0, 0)
            CATransaction.begin()
            if !isCleaned {
                for (i, view) in self.contentViews.enumerated() {
                    view?.removeFromSuperview()
                    self.contentViews[i] = nil
                }
            }
            isCleaned = true
            CATransaction.commit()
            return
        }
        
        
        CATransaction.begin()
        
        var unused:[ChatMediaContentView] = []
        for (i, data) in item.files.enumerated() {
            let file = data.0
            let point = data.2
            let viewType = data.1
            if NSPointInRect(point, visibleRect) {
                var view: ChatMediaContentView
                if self.contentViews[i] == nil || !self.contentViews[i]!.isKind(of: viewType) {
                    if unused.isEmpty {
                        view = viewType.init(frame: NSZeroRect)
                    } else {
                        view = unused.removeFirst()
                    }
                    self.contentViews[i] = view
                } else {
                    view = self.contentViews[i]!
                }
                if view.media?.id != file.id {
                    let size = file.dimensions?.size.aspectFitted(size) ?? size
                    view.update(with: file, size: size, context: item.context, parent: nil, table: item.table)
                }
                view.userInteractionEnabled = false
                view.setFrameOrigin(point)
                
            } else {
                if let view = self.contentViews[i] {
                    unused.append(view)
                    self.contentViews[i] = nil
                }
            }
        }
        
        for view in unused {
            view.clean()
            view.removeFromSuperview()
        }
        
        self.subviews = (self.clearRecentButton != nil ? [self.clearRecentButton!] : []) + (self.addButton != nil ? [self.addButton!] : []) + [self.packNameView] + self.contentViews.compactMap { $0 }
                
        CATransaction.commit()
        
        
    }
    
    override func viewDidMoveToWindow() {
        if window == nil {
            NotificationCenter.default.removeObserver(self)
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(updateVisibleItems), name: NSView.boundsDidChangeNotification, object: self.enclosingScrollView?.contentView)
        }
        updateVisibleItems()
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StickerPackPanelRowItem else {
            return
        }
        
        packNameView.update(item.packNameLayout)
        
        if item.arguments.mode == .common {
            switch item.packInfo {
            case .recent:
                if self.clearRecentButton == nil {
                    self.clearRecentButton = ImageButton()
                    addSubview(self.clearRecentButton!)
                }
                self.clearRecentButton?.set(image: theme.icons.wallpaper_color_close, for: .Normal)
                _ = self.clearRecentButton?.sizeToFit(NSMakeSize(5, 5), thatFit: false)
                
                self.clearRecentButton?.removeAllHandlers()
                
                self.clearRecentButton?.set(handler: { [weak item] _ in
                    item?.arguments.clearRecent()
                }, for: .Click)
            default:
                self.clearRecentButton?.removeFromSuperview()
                self.clearRecentButton = nil
            }
        } else {
            self.clearRecentButton?.removeFromSuperview()
            self.clearRecentButton = nil
        }
       
        
        self.previousRange = (0, 0)
        
        while self.contentViews.count > item.files.count {
            self.contentViews.removeLast()
        }
        while self.contentViews.count < item.files.count {
            self.contentViews.append(nil)
        }
        
        self.addButton?.removeFromSuperview()
        self.addButton = nil
        
        if let reference = item.packReference, item.packInfo.featured {
            if !item.packInfo.installed {
                self.addButton = TitleButton()
                self.addButton!.set(background: theme.colors.accentSelect, for: .Normal)
                self.addButton!.set(background: theme.colors.accentSelect.withAlphaComponent(0.8), for: .Highlight)
                self.addButton!.set(font: .medium(.text), for: .Normal)
                self.addButton!.set(color: theme.colors.underSelectedColor, for: .Normal)
                self.addButton!.set(text: strings().stickersSearchAdd, for: .Normal)
                _ = self.addButton!.sizeToFit(NSMakeSize(14, 8), thatFit: true)
                self.addButton!.layer?.cornerRadius = .cornerRadius
                self.addButton!.setFrameOrigin(frame.width - self.addButton!.frame.width - 10, 13)
                
                self.addButton!.set(handler: { [weak item] _ in
                    item?.arguments.addPack(reference)
                }, for: .Click)
            } else {
                self.addButton = TitleButton()
                self.addButton!.set(background: theme.colors.grayForeground, for: .Normal)
                self.addButton!.set(background: theme.colors.grayForeground.withAlphaComponent(0.8), for: .Highlight)
                self.addButton!.set(font: .medium(.text), for: .Normal)
                self.addButton!.set(color: theme.colors.underSelectedColor, for: .Normal)
                self.addButton!.set(text: strings().stickersSearchAdded, for: .Normal)
                _ = self.addButton!.sizeToFit(NSMakeSize(14, 8), thatFit: true)
                self.addButton!.layer?.cornerRadius = .cornerRadius
                self.addButton!.setFrameOrigin(frame.width - self.addButton!.frame.width - 10, 13)
                
                self.addButton!.set(handler: { [weak item] _ in
                    if let item = item {
                        item.arguments.removePack(item.collectionId)
                    }
                },  for: .Click)
            }
        }
        
        updateVisibleItems()
    }
    
}
