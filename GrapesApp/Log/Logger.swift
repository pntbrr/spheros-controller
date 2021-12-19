//
//  Logger.swift
//  GrapesApp
//
//  Created by Ponk on 19/12/2021.
//

import Foundation
import UIKit

class Log {
    public static let i = Log()
    private init() {}
    
    private var textView: UITextView?
    
    func print(_ data: Any) {
        textView?.text += "\n\(data)"
    }
    func setTarget (target: UITextView) {
        self.textView = target
    }
}
