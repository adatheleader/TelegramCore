
import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
    import MtProtoKitMac
#else
    import Postbox
    import SwiftSignalKit
    import MtProtoKitDynamic
#endif


public struct TelegramPeerPhoto {
    public let image: TelegramMediaImage
    public let date: Int32
    public let reference: TelegramMediaImageReference?
    public let index:Int
    public let totalCount:Int
}

public func requestPeerPhotos(account:Account, peerId: PeerId) -> Signal<[TelegramPeerPhoto], NoError> {
    return account.postbox.transaction{ transaction -> Peer? in
        return transaction.getPeer(peerId)
    }
    |> mapToSignal { peer -> Signal<[TelegramPeerPhoto], NoError> in
            if let peer = peer as? TelegramUser, let inputUser = apiInputUser(peer) {
                return account.network.request(Api.functions.photos.getUserPhotos(userId: inputUser, offset: 0, maxId: 0, limit: 100))
                |> map {Optional($0)}
                |> mapError {_ in}
                |> `catch` { _ -> Signal<Api.photos.Photos?, NoError> in
                    return .single(nil)
                }
                |> map { result -> [TelegramPeerPhoto] in
                    
                    if let result = result {
                        let totalCount:Int
                        let photos:[Api.Photo]
                        switch result {
                        case let .photos(data):
                            photos = data.photos
                            totalCount = photos.count
                        case let .photosSlice(data):
                            photos = data.photos
                            totalCount = Int(data.count)
                        }
                        
                        var images:[TelegramPeerPhoto] = []
                        for i in 0 ..< photos.count {
                            let photo = photos[i]
                            let image:TelegramMediaImage
                            let reference: TelegramMediaImageReference
                            let date: Int32
                            switch photo {
                            case let .photo(data):
                                date = data.date
                                reference = .cloud(imageId: data.id, accessHash: data.accessHash, fileReference: data.fileReference.makeData())
                                image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: data.id), representations: telegramMediaImageRepresentationsFromApiSizes(data.sizes), reference: reference, partialReference: nil)
                            case let .photoEmpty(id: id):
                                date = 0
                                reference = .cloud(imageId: id, accessHash: 0, fileReference: nil)
                                image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: id), representations: [], reference: reference, partialReference: nil)
                            }
                            images.append(TelegramPeerPhoto(image: image, date: date, reference: reference, index: i, totalCount: totalCount))
                        }
                        
                        return images
                    } else {
                        return []
                    }
                }
            } else if let peer = peer, let inputPeer = apiInputPeer(peer) {
                return account.network.request(Api.functions.messages.search(flags: 0, peer: inputPeer, q: "", fromId: nil, filter: .inputMessagesFilterChatPhotos, minDate: 0, maxDate: 0, offsetId: 0, addOffset: 0, limit: 1000, maxId: 0, minId: 0, hash: 0))
                |> map(Optional.init)
                |> `catch` { _ -> Signal<Api.messages.Messages?, NoError> in
                    return .single(nil)
                }
                |> mapToSignal { result -> Signal<[TelegramPeerPhoto], NoError> in
                    if let result = result {
                        let messages: [Api.Message]
                        let chats: [Api.Chat]
                        let users: [Api.User]
                        switch result {
                            case let .channelMessages(_, _, _, apiMessages, apiChats, apiUsers):
                                messages = apiMessages
                                chats = apiChats
                                users = apiUsers
                            case let .messages(apiMessages, apiChats, apiUsers):
                                messages = apiMessages
                                chats = apiChats
                                users = apiUsers
                            case let.messagesSlice(_, apiMessages, apiChats, apiUsers):
                                messages = apiMessages
                                chats = apiChats
                                users = apiUsers
                            case .messagesNotModified:
                                messages = []
                                chats = []
                                users = []
                        }
                        
                        return account.postbox.transaction { transaction -> [Message] in
                            var peers: [PeerId: Peer] = [:]
                            
                            for user in users {
                                if let user = TelegramUser.merge(transaction.getPeer(user.peerId) as? TelegramUser, rhs: user) {
                                    peers[user.id] = user
                                }
                            }
                            
                            for chat in chats {
                                if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                                    peers[groupOrChannel.id] = groupOrChannel
                                }
                            }
                            
                            var renderedMessages: [Message] = []
                            for message in messages {
                                if let message = StoreMessage(apiMessage: message), let renderedMessage = locallyRenderedMessage(message: message, peers: peers) {
                                    renderedMessages.append(renderedMessage)
                                }
                            }
                            
                            return renderedMessages
                        } |> map { messages -> [TelegramPeerPhoto] in
                            var photos:[TelegramPeerPhoto] = []
                            var index:Int = 0
                            for message in messages {
                                if let media = message.media.first as? TelegramMediaAction {
                                    switch media.action {
                                    case let .photoUpdated(image):
                                        if let image = image {
                                            photos.append(TelegramPeerPhoto(image: image, date: message.timestamp, reference: nil, index: index, totalCount: messages.count))
                                        }
                                    default:
                                        break
                                    }
                                }
                                index += 1
                            }
                            return photos
                        }
                        
                    } else {
                        return .single([])
                    }
                }
            } else {
                return .single([])
            }
    }
}
