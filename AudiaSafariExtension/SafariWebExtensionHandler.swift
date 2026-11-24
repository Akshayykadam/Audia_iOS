//
//  SafariWebExtensionHandler.swift
//  AudiaSafariExtension
//

import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]

        os_log(.default, "AudiaSafariExtension received message: %@", String(describing: message))

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["status": "ok"]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
