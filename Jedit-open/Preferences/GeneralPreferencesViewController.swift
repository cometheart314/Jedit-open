//
//  GeneralPreferencesViewController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/29.
//

import Cocoa


// GeneralPreferencesViewController.swift
class GeneralPreferencesViewController: NSViewController {
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        let label = NSTextField(labelWithString: "一般設定")
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.frame = NSRect(x: 30, y: view.frame.height - 60, width: 300, height: 30)
        view.addSubview(label)
        
        let checkbox = NSButton(checkboxWithTitle: "起動時に自動的に開く", target: nil, action: nil)
        checkbox.frame = NSRect(x: 30, y: view.frame.height - 110, width: 300, height: 24)
        view.addSubview(checkbox)
    }
}
