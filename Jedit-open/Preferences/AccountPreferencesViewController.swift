//
//  AccountPreferencesViewController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/29.
//

// AccountPreferencesViewController.swift

import Cocoa


class AccountPreferencesViewController: NSViewController {
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let label = NSTextField(labelWithString: "アカウント設定")
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.frame = NSRect(x: 30, y: view.frame.height - 60, width: 300, height: 30)
        view.addSubview(label)
    }
}
