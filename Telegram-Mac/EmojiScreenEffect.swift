//
//  EmojiScreenEffect.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 14.09.2021.
//  Copyright © 2021 Telegram. All rights reserved.
//

import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox

final class EmojiScreenEffect {
    fileprivate let context: AccountContext
    fileprivate let takeTableItem:(MessageId)->TableRowItem?
    fileprivate(set) var scrollUpdater: TableScrollListener!
    private let dataDisposable: DisposableDict<String> = DisposableDict()
    private let reactionDataDisposable: DisposableDict<String> = DisposableDict()
    
    private let limit: Int = 5
    
    struct Key : Hashable {
        enum Mode : Equatable, Hashable {
            case effect
            case reaction(String)
        }
        let animationKey: LottieAnimationKey
        let messageId: MessageId
        let timestamp: TimeInterval
        let isIncoming: Bool
        let mode: Mode
        
        var screenMode: ChatRowView.ScreenEffectMode {
            switch self.mode {
            case let .reaction(value):
                return .reaction(value)
            case .effect:
                return .effect
            }
        }
    }
    
    struct Value {
        let view: WeakReference<EmojiAnimationEffectView>
        let index: Int
        let emoji: String
        let mirror: Bool
        let key: Key
    }
    
    private var animations:[Key: Value] = [:]
    
    private var enqueuedToServer:[Value] = []
    private var enqueuedToEnjoy:[Value] = []
    
    private var enjoyTimer: SwiftSignalKit.Timer?

    private var timers:[MessageId : SwiftSignalKit.Timer] = [:]
    
    
    
    init(context: AccountContext, takeTableItem:@escaping(MessageId)->TableRowItem?) {
        self.context = context
        self.takeTableItem = takeTableItem
        
        self.scrollUpdater = .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateScroll(transition: .immediate)
        })
    }
    
    private func checkItem(_ item: TableRowItem, _ messageId: MessageId, with emoji: String) -> Bool {
        if let item = item as? ChatRowItem, item.message?.text == emoji {
            if messageId.peerId.namespace == Namespaces.Peer.CloudUser {
                return context.sharedContext.baseSettings.bigEmoji
            }
        }
        return false
    }
    
    private func updateScroll(transition: ContainedViewLayoutTransition) {
        var outOfBounds: Set<Key> = Set()
        for (key, animation) in animations {
            var success: Bool = false
            if let animationView = animation.view.value {
                if let item = takeTableItem(key.messageId), let view = item.view as? ChatRowView {
                    if let contentView = view.getScreenEffectView(key.screenMode) {
                        var point = contentView.convert(CGPoint.zero, to: animationView)
                        let subSize = animationView.animationSize - contentView.frame.size
                        
                        switch key.mode {
                        case .effect:
                            point.x-=(subSize.width - 20)
                            point.y-=subSize.height/2
                        case .reaction:
                            point.x-=subSize.width/2
                            point.y-=subSize.height/2
                        }
                       

                        
                        animationView.updatePoint(point, transition: transition)
                        
                        if contentView.visibleRect != .zero {
                            success = true
                        }
                    }
                }
            }
            if !success {
                outOfBounds.insert(key)
            }
        }
        for key in outOfBounds {
            self.deinitAnimation(key: key, animated: true)
        }
    }
    
    deinit {
        dataDisposable.dispose()
        reactionDataDisposable.dispose()
        let animations = self.animations
        for animation in animations {
            deinitAnimation(key: animation.key, animated: false)
        }
    }
    private func isLimitExceed(_ messageId: MessageId) -> Bool {
        let onair = animations.filter { $0.key.messageId == messageId }
        let last = onair.max(by: { $0.key.timestamp < $1.key.timestamp })
        if let last = last {
            if Date().timeIntervalSince1970 - last.key.timestamp < 0.2 {
                return true
            }
        }
        return onair.count >= limit
    }
    
    
    func addAnimation(_ emoji: String, index: Int?, mirror: Bool, isIncoming: Bool, messageId: MessageId, animationSize: NSSize, viewFrame: NSRect, for parentView: NSView) {
        
        if !isLimitExceed(messageId), let item = takeTableItem(messageId), checkItem(item, messageId, with: emoji) {
            let signal: Signal<LottieAnimation?, NoError> = context.diceCache.animationEffect(for: emoji.emojiUnmodified)
            |> map { value -> LottieAnimation? in
                if let random = value.randomElement(), let data = random.1 {
                    return LottieAnimation(compressed: data, key: .init(key: .bundle("_effect_\(emoji)"), size: animationSize, backingScale: Int(System.backingScale)), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd)
                } else {
                    return nil
                }
            }
            |> deliverOnMainQueue
            
            dataDisposable.set(signal.start(next: { [weak self, weak parentView] animation in
                if let animation = animation, let parentView = parentView {
                    self?.initAnimation(animation, mode: .effect, emoji: emoji, mirror: mirror, isIncoming: isIncoming, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
                }
            }), forKey: emoji)
        } else {
            dataDisposable.set(nil, forKey: emoji)
        }
    }
    
    func addReactionAnimation(_ value: String, index: Int?, messageId: MessageId, animationSize: NSSize, viewFrame: NSRect, for parentView: NSView) {
        
        let context = self.context
        
        let signal: Signal<LottieAnimation?, NoError> = context.reactions.stateValue |> take(1) |> map {
            return $0?.reactions.first(where: {
                $0.value == value
            })
        }
        |> filter { $0 != nil}
        |> map {
            $0!
        } |> mapToSignal { reaction -> Signal<MediaResourceData, NoError> in
            if let file = reaction.aroundAnimation {
                return context.account.postbox.mediaBox.resourceData(file.resource)
                |> filter { $0.complete }
                |> take(1)
            } else {
                return .complete()
            }
        } |> map { data in
            if let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                return LottieAnimation(compressed: data, key: .init(key: .bundle("_reaction_e_\(value)"), size: animationSize, backingScale: Int(System.backingScale)), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd)
            } else {
                return nil
            }
        } |> deliverOnMainQueue
        
        reactionDataDisposable.set(signal.start(next: { [weak self, weak parentView] animation in
            if let animation = animation, let parentView = parentView {
                self?.initAnimation(animation, mode: .reaction(value), emoji: value, mirror: false, isIncoming: false, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
            }
        }), forKey: value)
       
    }

    
    
    private func deinitAnimation(key: Key, animated: Bool) {
        let view = animations.removeValue(forKey: key)?.view.value
        if let view = view {
            performSubviewRemoval(view, animated: animated)
        }
        enqueuedToServer.removeAll(where: { $0.key == key })
        enqueuedToEnjoy.removeAll(where: { $0.key == key })
    }
    
    func removeAll() {
        let animations = self.animations
        for animation in animations {
            deinitAnimation(key: animation.key, animated: false)
        }
    }
    
    private func initAnimation(_ animation: LottieAnimation, mode: EmojiScreenEffect.Key.Mode, emoji: String, mirror: Bool, isIncoming: Bool, messageId: MessageId, animationSize: NSSize, viewFrame: NSRect, parentView: NSView) {
        
        
        let mediaView = (takeTableItem(messageId)?.view as? ChatMediaView)?.contentNode as? MediaAnimatedStickerView
        mediaView?.playAgain()
        
        let key: Key = .init(animationKey: animation.key.key, messageId: messageId, timestamp: Date().timeIntervalSince1970, isIncoming: isIncoming, mode: mode)
        
        animation.triggerOn = (LottiePlayerTriggerFrame.last, { [weak self] in
            self?.deinitAnimation(key: key, animated: true)
        }, {})
        
        let view = EmojiAnimationEffectView(animation: animation, animationSize: animationSize, animationPoint: .zero, frameRect: viewFrame, mirror: mirror)

        parentView.addSubview(view)
        
        let value: Value = .init(view: .init(value: view), index: 1, emoji: emoji, mirror: mirror, key: key)
        animations[key] = value
        
        updateScroll(transition: .immediate)
        if !isIncoming {
            self.enqueuedToServer.append(value)
        } else {
            self.enqueuedToEnjoy.append(value)
        }
        self.enqueueToServer()
        self.enqueueToEnjoy()
    }
    
    private func enqueueToEnjoy() {
        if enjoyTimer == nil, !enqueuedToEnjoy.isEmpty {
            enjoyTimer = .init(timeout: 1.0, repeat: false, completion: { [weak self] in
                self?.performEnjoyAction()
            }, queue: .mainQueue())
            enjoyTimer?.start()
        }
    }
    
    private func performEnjoyAction() {
        self.enjoyTimer = nil
        
        var exists:Set<MessageId> = Set()
        for value in enqueuedToEnjoy {
            if !exists.contains(value.key.messageId) {
                context.account.updateLocalInputActivity(peerId: PeerActivitySpace(peerId: value.key.messageId.peerId, category: .global), activity: .seeingEmojiInteraction(emoticon: value.emoji), isPresent: true)
                exists.insert(value.key.messageId)
            }
        }
        self.enqueuedToEnjoy.removeAll()
    }
    
    private func enqueueToServer() {
        let outgoing = self.enqueuedToServer
        let msgIds:[MessageId] = outgoing.map { $0.key.messageId }.uniqueElements
 
        for msgId in msgIds {
            if self.timers[msgId] == nil {
                self.timers[msgId] = .init(timeout: 1, repeat: false, completion: { [weak self] in
                    self?.performServerActions(for: msgId)
                }, queue: .mainQueue())
                self.timers[msgId]?.start()
            }
        }
    }
    
    private func performServerActions(for msgId: MessageId) {
        let values = self.enqueuedToServer.filter { $0.key.messageId == msgId }
        self.enqueuedToServer.removeAll(where: { $0.key.messageId == msgId })
        self.timers.removeValue(forKey: msgId)
        if !values.isEmpty {
            let value = values.min(by: { $0.key.timestamp < $1.key.timestamp })!
            let animations:[EmojiInteraction.Animation] = values.map { current -> EmojiInteraction.Animation in
                .init(index: current.index, timeOffset: Float((current.key.timestamp - value.key.timestamp)))
            }.sorted(by: { $0.timeOffset < $1.timeOffset })
            
            context.account.updateLocalInputActivity(peerId: PeerActivitySpace(peerId: msgId.peerId, category: .global), activity: .interactingWithEmoji(emoticon: value.emoji, messageId: msgId, interaction: EmojiInteraction(animations: animations)), isPresent: true)
        }
    }
    
    
    func updateLayout(rect: CGRect, transition: ContainedViewLayoutTransition) {
        for (_ , animation) in animations {
            if let value = animation.view.value {
                transition.updateFrame(view: value, frame: rect)
                value.updateLayout(size: rect.size, transition: transition)
                
                if animation.mirror {
                    let size = value.animationSize
                    var fr = CATransform3DIdentity
                    fr = CATransform3DTranslate(fr, size.width, 0, 0)
                    fr = CATransform3DScale(fr, -1, 1, 1)
                    fr = CATransform3DTranslate(fr, -(size.width + size.width/2), 0, 0)
                    value.layer?.sublayerTransform = fr
                } else {
                    value.layer?.sublayerTransform = CATransform3DIdentity
                }
                
            }
        }
    }
}
