//
//  TodoStore.swift
//  ReactActuallyNative
//
//  Created by Adlai Holler on 2/6/16.
//  Copyright © 2016 Adlai Holler. All rights reserved.
//

import Foundation
import CoreData
import ReactiveCocoa
import enum Result.NoError

final class TodoStore {
    enum Event {
        case Change(ManagedObjectContextChange)
    }

    private let changeObserver: Observer<Event, NoError>

    let changes: Signal<Event, NoError>
    let managedObjectContext: NSManagedObjectContext
    var dispatchToken: DispatchToken!
    init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
        (changes, changeObserver) = Signal<Event, NoError>.pipe()
        dispatchToken = dispatcher.register { [weak self] action in
            self?.handleAction(action)
        }
    }

    var editingItemID: NSManagedObjectID?

    func getAll() -> [TodoItem] {
        let fr = NSFetchRequest(entityName: "TodoItem")
        fr.sortDescriptors = [
            NSSortDescriptor(key: TodoItem.Property.id.rawValue, ascending: true)
        ]
        fr.returnsObjectsAsFaults = false
        var result: [TodoItem]?
        managedObjectContext.performBlockAndWait {
            result = try! (self.managedObjectContext.executeFetchRequest(fr) as! [NSManagedObject]).map(TodoItem.init)
        }
        return result!
    }

    private func handleAction(action: TodoAction) {
        switch action {
        case let .BeginEditingTitle(objectID):
            self.editingItemID = objectID
            changeObserver.sendNext(.Change(ManagedObjectContextChange()))
        case let .Create(title):
            managedObjectContext.performBlock {
                let changeOrNil = try? self.managedObjectContext.doWriteTransaction {
                    let item = TodoItem(id: TodoItem.maxId, title: title, completed: false)
                    TodoItem.incrementMaxID()
                    let obj = NSEntityDescription.insertNewObjectForEntityForName(TodoItem.entityName, inManagedObjectContext: self.managedObjectContext)
                    item.apply(obj)
                }
                if let change = changeOrNil {
                    self.changeObserver.sendNext(.Change(change))
                }
            }
        case let .UpdateText(objectID, newTitle):
            managedObjectContext.performBlock {
                let changeOrNil = try? self.managedObjectContext.doWriteTransaction {
                    let object = try self.managedObjectContext.existingObjectWithID(objectID)
                    var item = TodoItem(object: object)
                    item.title = newTitle
                    item.apply(object)
                    self.editingItemID = nil
                }
                if let change = changeOrNil {
                    self.changeObserver.sendNext(.Change(change))
                }
            }
        }
    }

}

extension NSManagedObjectContext {
    func doWriteTransaction(@noescape body: () throws -> Void) throws -> ManagedObjectContextChange {
        do {
            assert(!hasChanges, "Managed object context must be clean to do a write transaction.")
            try body()
            try obtainPermanentIDsForObjects(Array(insertedObjects))
            var change: ManagedObjectContextChange?
            NSNotificationCenter.defaultCenter()
                .rac_notifications(NSManagedObjectContextDidSaveNotification, object: self)
                .take(1)
                .startWithNext { change = ManagedObjectContextChange(notification: $0) }
            try save()
            return change!
        } catch let e {
            rollback()
            throw e
        }
    }
}