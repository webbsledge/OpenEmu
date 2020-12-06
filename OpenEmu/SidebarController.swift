// Copyright (c) 2020, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Cocoa

extension NSPasteboard.PasteboardType {
    static let game = NSPasteboard.PasteboardType("org.openemu.game")
}

extension NSNotification.Name {
    static let OESidebarSelectionDidChange = NSNotification.Name("OESidebarSelectionDidChange")
}

@objc(OESidebarController)
class SidebarController: NSViewController {
    
    @IBOutlet var sidebarView: NSOutlineView!
    @IBOutlet var gameScannerViewController: GameScannerViewController!
    
    var database: OELibraryDatabase? {
        didSet {
            let lastSidebarSelection = self.lastSidebarSelection
            reloadData()
            self.lastSidebarSelection = lastSidebarSelection
            
            guard
                !lastSidebarSelection.isEmpty,
                let item = lastSidebarSelectionItem
                else { return }
            
            selectItem(item)
        }
    }
    
    @UserDefault(.lastSidebarSelection, defaultValue: "")
    var lastSidebarSelection: String
    
    var lastSidebarSelectionItem: OESidebarItem? {
        systems.first(where: { $0.sidebarID == lastSidebarSelection }) ?? collections.first(where: { $0.sidebarID == lastSidebarSelection})
    }
    
    var groups = [
        SidebarGroupItem(name: NSLocalizedString("Consoles", comment: ""),
                    autosaveName: .sidebarConsolesItem),
        SidebarGroupItem(name: NSLocalizedString("Collections", comment: ""),
                    autosaveName: .sidebarCollectionsItem)
    ]
    
    var systems: [OESidebarItem] = []
    var collections: [OESidebarItem] = []
    
    var selectedSidebarItem: OESidebarItem? {
        let item = sidebarView.item(atRow: sidebarView.selectedRow)
        precondition(item == nil || item is OESidebarItem, "All sidebar items must confirm to OESidebarItem")
        return item as? OESidebarItem
    }
    
    private var token: NSObjectProtocol?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sidebarView.register(NSNib(nibNamed: "SidebarHeaderView", bundle: nil), forIdentifier: Self.headerViewIdentifier)
        sidebarView.register(NSNib(nibNamed: "SidebarItemView", bundle: nil), forIdentifier: Self.itemViewIdentifier)
        
        sidebarView.registerForDraggedTypes([.fileURL, .game])
        sidebarView.expandItem(nil, expandChildren: true)
        
        let menu = NSMenu()
        menu.delegate = self
        sidebarView.menu = menu
        menuNeedsUpdate(menu)
        
        token = NotificationCenter.default.addObserver(forName: .OEDBSystemAvailabilityDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            
            self.reloadDataAndPreserveSelection()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(libraryLocationDidChange(_:)), name: .OELibraryLocationDidChange, object: nil)
    }
    
    func reloadDataAndPreserveSelection() {
        let possibleItem = self.selectedSidebarItem
        let previousRow  = self.sidebarView.selectedRow
        
        reloadData()
        
        guard let previousItem = possibleItem else { return }
        
        var rowToSelect = previousRow
        let reloadedRowForPreviousItem = sidebarView.row(forItem: previousItem)
        
        if reloadedRowForPreviousItem == -1 {
            func isSelectable(i: Int) -> Bool {
                guard let item = sidebarView.item(atRow: i) else { return false }
                return outlineView(sidebarView, shouldSelectItem: item)
            }
            
            rowToSelect =
                // find a row before the previously selected one
                (0...rowToSelect).reversed().first(where: isSelectable) ??
                
                // find a row after the previously selected one
                (rowToSelect..<sidebarView.numberOfRows).first(where: isSelectable) ??
                
                // or nothing
                NSNotFound
            
        } else if reloadedRowForPreviousItem != previousRow {
            rowToSelect = reloadedRowForPreviousItem
        }
        
        guard rowToSelect != NSNotFound else { return }
        
        sidebarView.selectRowIndexes([rowToSelect], byExtendingSelection: false)
        outlineViewSelectionDidChange(Notification(name: NSOutlineView.selectionDidChangeNotification))
    }
    
    func reloadData() {
        guard let database = database else { return }
        
        systems     = OEDBSystem.enabledSystemsinContext(database.mainThreadContext) ?? []
        collections = database.collections
        sidebarView.reloadData()
    }
    
    @objc func libraryLocationDidChange(_ notification: Notification) {
        reloadData()
    }
    
    // MARK: - Actions
    
    func selectItem(_ item: OESidebarItem) {
        guard item.isSelectableInSidebar else { return }
        
        let index = sidebarView.row(forItem: item)
        guard index > -1 else { return }
        
        if sidebarView.selectedRow != index {
            sidebarView.selectRowIndexes([index], byExtendingSelection: false)
        }
    }
    
    func startEditingItem(_ item: OESidebarItem) {
        guard item.isSelectableInSidebar else { return }
        
        let index = sidebarView.row(forItem: item)
        guard index > -1 else { return }
        
        let event = NSEvent()
        sidebarView.editColumn(0, row: index, with: event, select: true)
    }
    
    @IBAction func endedEditingItem(_ sender: NSTextField) {
        let index = sidebarView.row(for: sender)
        
        if let item = sidebarView.item(atRow: index) as? OEDBCollection,
           !sender.stringValue.isEmpty {
            item.name = sender.stringValue
            item.save()
        }
        
        reloadDataAndPreserveSelection()
    }
    
    func renameItem(at index: Int) {
        guard let item = sidebarView.item(atRow: index) as? OESidebarItem else { return }
        
        selectItem(item)
        startEditingItem(item)
    }
    
    private func removeItem(at index: Int) {
        guard let item = sidebarView.item(atRow: index) as? OEDBCollection,
              item.isEditableInSidebar,
              OEAlert.removeCollection(name: item.sidebarName).runModal() == .alertFirstButtonReturn else { return }
        
        item.delete()
        item.save()
        
        // keep selection on last object if the one we removed was last
        var index = index
        if sidebarView.selectedRowIndexes.first != index {
            index = sidebarView.selectedRowIndexes.first ?? index
        }
        else if index == sidebarView.numberOfRows - 1 {
            index -= 1
        }
        
        reloadData()
        sidebarView.selectRowIndexes([index], byExtendingSelection: false)
    }
    
    @objc func addCollection() -> OEDBCollection {
        let newCollection = database!.addNewCollection(nil)
        
        reloadData()
        selectItem(newCollection)
        startEditingItem(newCollection)
        
        return newCollection
    }
    
    @IBAction func newCollection(_ sender: AnyObject?) {
        _ = addCollection()
    }
    
    func newCollection(games: [OEDBGame]) {
        let newCollection = database!.addNewCollection(nil)
        
        newCollection.games = Set(games)
        if games.count == 1 {
            newCollection.name = games.first?.displayName
        }
        newCollection.save()
        
        reloadData()
        selectItem(newCollection)
        startEditingItem(newCollection)
    }
    
    @objc func duplicateCollection(_ originalCollection: Any?) {
        guard let originalCollection = originalCollection as? OEDBCollection,
              let originalName = originalCollection.value(forKey: "name") as? String else { return }
        
        let duplicateName = String.localizedStringWithFormat(NSLocalizedString("%@ copy", comment: "Duplicated collection name"), originalName)
        let duplicateCollection = database!.addNewCollection(duplicateName)
        duplicateCollection.games = originalCollection.games
        duplicateCollection.save()
        
        reloadDataAndPreserveSelection()
    }
    
    @objc func renameItem(for menuItem: NSMenuItem) {
        renameItem(at: menuItem.tag)
    }
    
    @objc func removeItem(for menuItem: NSMenuItem) {
        removeItem(at: menuItem.tag)
    }
    
    @objc func removeSelectedItems() {
        guard let index = sidebarView.selectedRowIndexes.first else { return }
        
        removeItem(at: index)
    }
    
    @objc func duplicateCollection(for menuItem: NSMenuItem) {
        duplicateCollection(menuItem.representedObject)
    }
    
    @objc func toggleSystem(for menuItem: NSMenuItem) {
        let system = menuItem.representedObject as? OEDBSystem
        system?.toggleEnabledAndPresentError()
    }
    
    @objc func changeDefaultCore(_ sender: AnyObject?) {
        guard let data = sender?.representedObject as? [AnyHashable : Any],
              let systemIdentifier = data["system"] as? String,
              let coreIdentifier = data["core"] as? String else { return }
        
        let defaultCoreKey = "defaultCore.\(systemIdentifier)"
        UserDefaults.standard.set(coreIdentifier, forKey: defaultCoreKey)
    }
    
    @IBAction func selectSystems(_ sender: Any?) {
        guard let v = sender as? NSView else { return }
        
        let selectLibraryController = AvailableLibrariesViewController()
        let po = NSPopover()
        po.behavior = .transient
        po.contentSize = NSSize(width: 200, height: 500)
        po.contentViewController = selectLibraryController
        selectLibraryController.transparentBackground = true
        po.show(relativeTo: v.frame, of: sidebarView, preferredEdge: .maxX)
    }
    
    @IBAction func showIssuesView(_ sender: NSButton) {
        presentAsSheet(gameScannerViewController)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117,
           let index = sidebarView.selectedRowIndexes.first,
           let item = sidebarView.item(atRow: index) as? OESidebarItem,
           item.isEditableInSidebar {
            
            removeSelectedItems()
        }
        else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Delegate

extension SidebarController: NSOutlineViewDelegate {
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let id = selectedSidebarItem?.sidebarID {
            lastSidebarSelection = id
        }
        NotificationCenter.default.post(name: .OESidebarSelectionDidChange, object: self, userInfo: nil)
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        false
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        true
    }
}

// MARK: - DataSource

extension NSUserInterfaceItemIdentifier: ExpressibleByStringLiteral {
    public init(stringLiteral: String) {
        self.init(stringLiteral)
    }
}

extension SidebarController: NSOutlineViewDataSource {
    static let headerViewIdentifier: NSUserInterfaceItemIdentifier = "SidebarHeaderView"
    static let itemViewIdentifier: NSUserInterfaceItemIdentifier = "SidebarItemView"
    static let rowViewIdentifier: NSUserInterfaceItemIdentifier = "SidebarRowView"
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case let group as SidebarGroupItem where group.autosaveName == .sidebarConsolesItem:
            return systems[index]
            
        case let group as SidebarGroupItem where group.autosaveName == .sidebarCollectionsItem:
            return collections[index]
            
        default:
            return groups[index]
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? OESidebarItem)?.isGroupHeaderInSidebar ?? false
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return groups.count
        }

        guard
            let _ = database,
            let item = item as? SidebarGroupItem
            else { return 0 }
        
        
        switch item.autosaveName {
        case .sidebarConsolesItem:
            return systems.count
        case .sidebarCollectionsItem:
            return collections.count
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        (item as? OESidebarItem)?.sidebarName
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? OESidebarItem else { return nil }
        
        var view: NSTableCellView?
        
        if item.isGroupHeaderInSidebar {
            view = outlineView.makeView(withIdentifier: Self.headerViewIdentifier, owner: self) as? NSTableCellView
            
        } else {
            view = outlineView.makeView(withIdentifier: Self.itemViewIdentifier, owner: self) as? NSTableCellView
            view?.imageView?.image = item.sidebarIcon
            view?.textField?.isSelectable = false
            view?.textField?.isEditable = item.isEditableInSidebar
        }
        
        view?.textField?.stringValue = item.sidebarName
        
        return view
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        false
    }
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 24
    }
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is SidebarGroupItem
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !(item is SidebarGroupItem)
    }
    
    // MARK: - Drag & Drop
    
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        
        let pboard = info.draggingPasteboard
        
        var collection: OEDBCollection?
        if item is OEDBCollection {
            
            collection = item as? OEDBCollection
        }
        else if item as? SidebarGroupItem == groups[1] {
            
            // create a new collection with a single game
            var name: String?
            if pboard.types?.contains(.game) ?? false {
                
                let games = pboard.readObjects(forClasses: [OEDBGame.self], options: nil) as! [OEDBGame]
                if games.count == 1 {
                    name = games.first?.displayName
                }
            }
            else {
                
                let games = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
                if games?.count == 1 {
                    name = games?.first?.deletingPathExtension().lastPathComponent.removingPercentEncoding
                }
            }
            collection = database!.addNewCollection(name)
            reloadData()
            let index = outlineView.row(forItem: collection)
            if index != NSNotFound {
                outlineView.selectRowIndexes([index], byExtendingSelection: false)
                NotificationCenter.default.post(name: .OESidebarSelectionDidChange, object: self, userInfo: nil)
            }
        }
        
        if pboard.types?.contains(.game) ?? false {
            
            guard let collection = collection else { return true }
            
            // just add to collection
            let games = pboard.readObjects(forClasses: [OEDBGame.self], options: nil) as! [OEDBGame]
            collection.mutableGames?.addObjects(from: games)
            collection.save()
        }
        else {
            
            // import and add to collection
            if let files = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                let collectionID = collection?.permanentID
                let importer = database!.importer
                importer.importItems(at: files, intoCollectionWith: collectionID)
            }
        }
        
        return true
    }
    
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        
        guard let types = info.draggingPasteboard.types,
              types.contains(.game) || types.contains(.fileURL),
              item is OESidebarItem else {
            return []
        }
        
        // Ignore anything that is between two rows
        if index != NSOutlineViewDropOnItemIndex {
            return []
        }
        
        // Allow drop on systems group, ignoring which system exactly is highlighted
        if item as? SidebarGroupItem == groups[0] || item is OEDBSystem {
            
            // Disallow drop on systems for already imported games
            if types.contains(.game) {
                return []
            }
            
            // For new games, change drop target to the consoles header
            outlineView.setDropItem(groups[0], dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }
        
        // Allow drop on regular collections
        if type(of: item as! OESidebarItem) === OEDBCollection.self {
            return .copy
        }
        
        // Allow drop on the collections header and on smart collections
        if item as? SidebarGroupItem == groups[1] || item is OEDBCollection || item is OEDBAllGamesCollection {
            
            // Find the first regular collection in the list
            var i = 0
            for collection in 0..<collections.count {
                if type(of: collections[collection]) === OEDBCollection.self {
                    break
                }
                i += 1
            }
            
            // Register as a drop just before that collection
            outlineView.setDropItem(groups[1], dropChildIndex: i)
            return .copy
        }
        
        // Everything else is disabled
        return []
    }
}

// MARK: - NSMenuDelegate

extension SidebarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        
        menu.removeAllItems()
        
        let index = sidebarView.clickedRow
        
        guard index != -1 else { return }
        let item = sidebarView.item(atRow: index) as! OESidebarItem
        
        var menuItem: NSMenuItem
        
        if item is SidebarGroupItem {
            return
        }
        else if item is OEDBSystem {
            
            if let cores = OECorePlugin.corePlugins(forSystemIdentifier: (item as! OEDBSystem).systemIdentifier),
               cores.count > 1 {
                
                let systemIdentifier = (item as! OEDBSystem).systemIdentifier!
                let defaultCoreKey = "defaultCore.\(systemIdentifier)"
                let defaultCoreIdentifier = UserDefaults.standard.object(forKey: defaultCoreKey) as? String
                
                let coreItem = NSMenuItem()
                coreItem.title = NSLocalizedString("Default Core", comment: "Sidebar context menu item to pick default core for a system")
                let submenu = NSMenu()
                
                cores.forEach { core in
                    let coreName = core.displayName
                    let systemIdentifier = (item as! OEDBSystem).systemIdentifier!
                    let coreIdentifier = core.bundleIdentifier
                    
                    let item = NSMenuItem()
                    item.title = coreName ?? ""
                    item.action = #selector(changeDefaultCore(_:))
                    item.state = coreIdentifier == defaultCoreIdentifier ? .on : .off
                    item.representedObject = ["core": coreIdentifier,
                                            "system": systemIdentifier]
                    submenu.addItem(item)
                }
                coreItem.submenu = submenu
                menu.addItem(coreItem)
            }
            
            menuItem = NSMenuItem()
            menuItem.title = .localizedStringWithFormat(NSLocalizedString("Hide \"%@\"", comment: ""), (item as! OEDBSystem).name)
            menuItem.action = #selector(toggleSystem(for:))
            menuItem.representedObject = item
            menu.addItem(menuItem)
        }
        else if item is OEDBCollection || item is OEDBAllGamesCollection {
            
            if item.isEditableInSidebar {
                
                menuItem = NSMenuItem()
                menuItem.title = .localizedStringWithFormat(NSLocalizedString("Rename \"%@\"", comment: "Rename collection sidebar context menu item"), item.sidebarName)
                menuItem.action = #selector(renameItem(for:))
                menuItem.tag = index
                menu.addItem(menuItem)
                
                menuItem = NSMenuItem()
                menuItem.title = NSLocalizedString("Duplicate Collection", comment: "")
                menuItem.action = #selector(duplicateCollection(for:))
                menuItem.representedObject = item
                menu.addItem(menuItem)
                
                menuItem = NSMenuItem()
                menuItem.title = NSLocalizedString("Delete Collection", comment: "")
                menuItem.action = #selector(removeItem(for:))
                menuItem.tag = index
                menu.addItem(menuItem)
                
                menu.addItem(NSMenuItem.separator())
            }
            
            menuItem = NSMenuItem()
            menuItem.title = NSLocalizedString("New Collection", comment: "")
            menuItem.action = #selector(newCollection(_:))
            menu.addItem(menuItem)
        }
    }
}

class SidebarGroupItem: NSObject, OESidebarItem {
    
    enum AutosaveName: String {
        case sidebarConsolesItem, sidebarCollectionsItem
    }
    
    var name: String
    var autosaveName: AutosaveName
    
    init(name: String, autosaveName: AutosaveName) {
        self.name = name
        self.autosaveName = autosaveName
    }
    
    var sidebarIcon: NSImage?
    var sidebarName: String {
        return self.name
    }
    var sidebarID: String?
    var viewControllerClassName: String?
    var isSelectableInSidebar: Bool = false
    var isEditableInSidebar: Bool = false
    var isGroupHeaderInSidebar: Bool = true
    var hasSubCollections: Bool = false
    
}

extension Key {
    static let lastSidebarSelection: Key = "lastSidebarSelection"
}
