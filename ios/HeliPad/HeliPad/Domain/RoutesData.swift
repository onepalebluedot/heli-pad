import Foundation

public enum SeedData {
    public static let defaultLocations: [LocationItem] = [
        LocationItem(name: "Home", address: "18 Redwood Lane", icon: "house", latitude: 42.2808, longitude: -83.7430),
        LocationItem(name: "Product Office", address: "300 Innovation Drive", icon: "building-2", latitude: 42.2980, longitude: -83.7120),
        LocationItem(name: "Warren Plant", address: "Manufacturing Campus", icon: "factory", latitude: 42.5140, longitude: -83.0270),
        LocationItem(name: "Oak Ridge Elementary", address: "2140 Schoolhouse Road", icon: "school", latitude: 42.2780, longitude: -83.7400),
        LocationItem(name: "Lakeside Sports Complex", address: "803 Lakeview Drive", icon: "trophy", latitude: 42.2650, longitude: -83.7150),
        LocationItem(name: "North Athletic Field", address: "880 Northfield Road", icon: "goal", latitude: 42.2950, longitude: -83.7320),
        LocationItem(name: "Pediatric Clinic", address: "590 Health Parkway", icon: "hospital", latitude: 42.2920, longitude: -83.7210),
        LocationItem(name: "Community Center", address: "1440 Maple Avenue", icon: "music-2", latitude: 42.2850, longitude: -83.7380),
        LocationItem(name: "Downtown Square", address: "1 Market Plaza", icon: "store", latitude: 42.2810, longitude: -83.7480),
        LocationItem(name: "Kroger Pickup", address: "420 Grocery Way", icon: "shopping-cart", latitude: 42.2630, longitude: -83.7390)
    ]

    public static let defaultPeople: [Person] = [
        Person(id: "p1", name: "Mom", relationship: "Mother", kind: "caregiver", color: "#c75f45"),
        Person(id: "p2", name: "Dad", relationship: "Father", kind: "caregiver", color: "#397cad"),
        Person(id: "p3", name: "Nani", relationship: "Grandmother", kind: "caregiver", color: "#8f55a0"),
        Person(id: "p4", name: "Grandma", relationship: "Grandmother", kind: "caregiver", color: "#3f806e"),
        Person(id: "p5", name: "Soni", relationship: "Child", kind: "child", color: "#a8672b"),
        Person(id: "p6", name: "Maya", relationship: "Child", kind: "child", color: "#5a6ea8"),
        Person(id: "p7", name: "Noah", relationship: "Child", kind: "child", color: "#8a6d3b")
    ]

    public static let defaultTemplates: [TemplateItem] = [
        TemplateItem(id: "tpl_1", title: "School Morning Drop-off", time: "07:35", endTime: "08:05", kids: ["Soni"], kid: "Soni", owner: "Dad", location: "Oak Ridge Elementary", mode: "Drive", duration: 30, category: "School"),
        TemplateItem(id: "tpl_2", title: "Soccer Practice", time: "17:15", endTime: "18:30", kids: ["Noah"], kid: "Noah", owner: "Dad", location: "Lakeside Sports Complex", mode: "Drive", duration: 75, category: "Sports"),
        TemplateItem(id: "tpl_3", title: "Football Practice Pickup", time: "15:20", endTime: "16:20", kids: ["Maya"], kid: "Maya", owner: "Mom", location: "North Athletic Field", mode: "Drive", duration: 60, category: "Sports"),
        TemplateItem(id: "tpl_4", title: "Piano Lesson & Rehearsal", time: "16:00", endTime: "16:45", kids: ["Maya"], kid: "Maya", owner: "Mom", location: "Community Center", mode: "Drive", duration: 45, category: "Arts"),
        TemplateItem(id: "tpl_5", title: "Pediatric Wellness Visit", time: "13:40", endTime: "14:25", kids: ["Soni", "Maya", "Noah"], kid: "All", owner: "Mom", location: "Pediatric Clinic", mode: "Drive", duration: 45, category: "Health"),
        TemplateItem(id: "tpl_6", title: "Family Dinner & Game Night", time: "18:30", endTime: "20:00", kids: ["Soni", "Maya", "Noah"], kid: "All", owner: "Family", location: "Home", mode: "Home", duration: 90, category: "Family")
    ]

    public static let routeMatrix: [String: [String: Int]] = [
        "Home": ["Home": 0, "Product Office": 28, "Warren Plant": 26, "Oak Ridge Elementary": 14, "Lakeside Sports Complex": 18, "North Athletic Field": 22, "Pediatric Clinic": 23, "Community Center": 16, "Downtown Square": 12, "Kroger Pickup": 11],
        "Product Office": ["Home": 28, "Product Office": 0, "Warren Plant": 21, "Oak Ridge Elementary": 19, "Lakeside Sports Complex": 24, "North Athletic Field": 17, "Pediatric Clinic": 12, "Community Center": 14, "Downtown Square": 18, "Kroger Pickup": 15],
        "Warren Plant": ["Home": 26, "Product Office": 21, "Warren Plant": 0, "Oak Ridge Elementary": 16, "Lakeside Sports Complex": 15, "North Athletic Field": 13, "Pediatric Clinic": 20, "Community Center": 18, "Downtown Square": 19, "Kroger Pickup": 17],
        "Oak Ridge Elementary": ["Home": 14, "Product Office": 19, "Warren Plant": 16, "Oak Ridge Elementary": 0, "Lakeside Sports Complex": 10, "North Athletic Field": 12, "Pediatric Clinic": 11, "Community Center": 9, "Downtown Square": 12, "Kroger Pickup": 4],
        "Lakeside Sports Complex": ["Home": 18, "Product Office": 24, "Warren Plant": 15, "Oak Ridge Elementary": 10, "Lakeside Sports Complex": 0, "North Athletic Field": 8, "Pediatric Clinic": 14, "Community Center": 11, "Downtown Square": 16, "Kroger Pickup": 12],
        "North Athletic Field": ["Home": 22, "Product Office": 17, "Warren Plant": 13, "Oak Ridge Elementary": 12, "Lakeside Sports Complex": 8, "North Athletic Field": 0, "Pediatric Clinic": 18, "Community Center": 12, "Downtown Square": 17, "Kroger Pickup": 14],
        "Pediatric Clinic": ["Home": 23, "Product Office": 12, "Warren Plant": 20, "Oak Ridge Elementary": 11, "Lakeside Sports Complex": 14, "North Athletic Field": 18, "Pediatric Clinic": 0, "Community Center": 8, "Downtown Square": 13, "Kroger Pickup": 10],
        "Community Center": ["Home": 16, "Product Office": 14, "Warren Plant": 18, "Oak Ridge Elementary": 9, "Lakeside Sports Complex": 11, "North Athletic Field": 12, "Pediatric Clinic": 8, "Community Center": 0, "Downtown Square": 9, "Kroger Pickup": 7],
        "Downtown Square": ["Home": 12, "Product Office": 18, "Warren Plant": 19, "Oak Ridge Elementary": 12, "Lakeside Sports Complex": 16, "North Athletic Field": 17, "Pediatric Clinic": 13, "Community Center": 9, "Downtown Square": 0, "Kroger Pickup": 8],
        "Kroger Pickup": ["Home": 11, "Product Office": 15, "Warren Plant": 17, "Oak Ridge Elementary": 4, "Lakeside Sports Complex": 12, "North Athletic Field": 14, "Pediatric Clinic": 10, "Community Center": 7, "Downtown Square": 8, "Kroger Pickup": 0]
    ]

    public static func defaultEventsByDay(baseWeek: String = AppStore.BASE_WEEK) -> [Int: [TaskRecord]] {
        return [
            0: [
                TaskRecord(id: "101", date: PlanCore.dateAdd(baseWeek, 0), time: "13:40", endTime: "14:25", title: "Pediatric Checkup", owner: "Mom", kids: ["Maya"], kid: "Maya", location: "Pediatric Clinic", mode: "Drive", color: "#4f46e5"),
                TaskRecord(id: "102", date: PlanCore.dateAdd(baseWeek, 0), time: "14:30", endTime: "15:00", title: "School Pickup", owner: "Dad", kids: ["Soni"], kid: "Soni", location: "Oak Ridge Elementary", mode: "Drive", color: "#0284c7"),
                TaskRecord(id: "103", date: PlanCore.dateAdd(baseWeek, 0), time: "16:00", endTime: "16:45", title: "Piano Lesson", owner: "Mom", kids: ["Maya"], kid: "Maya", location: "Community Center", mode: "Drive", color: "#4f46e5"),
                TaskRecord(id: "104", date: PlanCore.dateAdd(baseWeek, 0), time: "17:15", endTime: "18:30", title: "Soccer Practice", owner: "Dad", kids: ["Soni"], kid: "Soni", location: "Lakeside Sports Complex", mode: "Drive", color: "#0284c7")
            ],
            1: [
                TaskRecord(id: "201", date: PlanCore.dateAdd(baseWeek, 1), time: "07:35", endTime: "08:15", title: "School Drop-off", owner: "Dad", kids: ["Soni"], kid: "Soni", location: "Oak Ridge Elementary", mode: "Drive", done: true, color: "#0284c7"),
                TaskRecord(id: "202", date: PlanCore.dateAdd(baseWeek, 1), time: "16:00", endTime: "17:00", title: "Pediatric Dental Appointment", owner: "Mom", kids: ["Soni"], kid: "Soni", location: "Pediatric Clinic", mode: "Drive", color: "#4f46e5"),
                TaskRecord(id: "203", date: PlanCore.dateAdd(baseWeek, 1), time: "16:45", endTime: "17:45", title: "Robotics Club Pickup", owner: "TBD", kids: ["Maya"], kid: "Maya", location: "Oak Ridge Elementary", mode: "Drive", color: "#f59e0b"),
                TaskRecord(id: "204", date: PlanCore.dateAdd(baseWeek, 1), time: "17:30", endTime: "18:30", title: "Piano Lesson", owner: "Nani", kids: ["Noah"], kid: "Noah", location: "Community Center", mode: "Drive", color: "#d946ef")
            ],
            2: [
                TaskRecord(id: "301", date: PlanCore.dateAdd(baseWeek, 2), time: "07:35", endTime: "08:15", title: "School Drop-off", owner: "Dad", kids: ["Soni"], kid: "Soni", location: "Oak Ridge Elementary", mode: "Drive", color: "#0284c7"),
                TaskRecord(id: "302", date: PlanCore.dateAdd(baseWeek, 2), time: "15:15", endTime: "16:30", title: "Gymnastics Clinic", owner: "Mom", kids: ["Maya", "Soni"], kid: "Maya, Soni", location: "Community Center", mode: "Drive", color: "#4f46e5"),
                TaskRecord(id: "303", date: PlanCore.dateAdd(baseWeek, 2), time: "17:00", endTime: "18:00", title: "Science Fair Project Setup", owner: "Dad", kids: ["Noah"], kid: "Noah", location: "Oak Ridge Elementary", mode: "Drive", color: "#0284c7"),
                TaskRecord(id: "304", date: PlanCore.dateAdd(baseWeek, 2), time: "18:15", endTime: "19:15", title: "Family Swimming", owner: "Mom", kids: ["Soni", "Maya", "Noah"], kid: "All", location: "Lakeside Sports Complex", mode: "Drive", color: "#4f46e5")
            ],
            3: [
                TaskRecord(id: "401", date: PlanCore.dateAdd(baseWeek, 3), time: "07:35", endTime: "08:15", title: "School Drop-off", owner: "Dad", kids: ["Soni"], kid: "Soni", location: "Oak Ridge Elementary", mode: "Drive", color: "#0284c7"),
                TaskRecord(id: "402", date: PlanCore.dateAdd(baseWeek, 3), time: "15:30", endTime: "16:30", title: "Math Olympiad Club Pickup", owner: "Grandma", kids: ["Noah"], kid: "Noah", location: "Oak Ridge Elementary", mode: "Drive", color: "#10b981"),
                TaskRecord(id: "403", date: PlanCore.dateAdd(baseWeek, 3), time: "17:15", endTime: "18:30", title: "Soccer Tournament Prep", owner: "Dad", kids: ["Noah"], kid: "Noah", location: "Lakeside Sports Complex", mode: "Drive", color: "#0284c7"),
                TaskRecord(id: "404", date: PlanCore.dateAdd(baseWeek, 3), time: "18:00", endTime: "19:00", title: "Art Studio Workshop", owner: "Mom", kids: ["Maya"], kid: "Maya", location: "Community Center", mode: "Drive", color: "#4f46e5")
            ],
            4: [
                TaskRecord(id: "501", date: PlanCore.dateAdd(baseWeek, 4), time: "07:35", endTime: "08:15", title: "School Drop-off", owner: "Dad", kids: ["Soni"], kid: "Soni", location: "Oak Ridge Elementary", mode: "Drive", color: "#0284c7"),
                TaskRecord(id: "502", date: PlanCore.dateAdd(baseWeek, 4), time: "13:00", endTime: "13:45", title: "Half-Day Early Dismissal", owner: "Grandma", kids: ["Soni", "Maya", "Noah"], kid: "All", location: "Oak Ridge Elementary", mode: "Drive", color: "#10b981"),
                TaskRecord(id: "503", date: PlanCore.dateAdd(baseWeek, 4), time: "16:00", endTime: "17:30", title: "Youth Orchestra Rehearsal", owner: "Mom", kids: ["Maya"], kid: "Maya", location: "Community Center", mode: "Drive", color: "#4f46e5"),
                TaskRecord(id: "504", date: PlanCore.dateAdd(baseWeek, 4), time: "18:30", endTime: "20:00", title: "Friday Pizza & Movie Night Ride", owner: "Family", kids: ["Soni", "Maya", "Noah"], kid: "All", location: "Home", mode: "Drive", color: "#d97706")
            ],
            5: [
                TaskRecord(id: "601", date: PlanCore.dateAdd(baseWeek, 5), time: "09:00", endTime: "11:00", title: "Weekend Soccer Tournament Game", owner: "Dad", kids: ["Noah", "Soni"], kid: "Noah, Soni", location: "Lakeside Sports Complex", mode: "Drive", color: "#0284c7"),
                TaskRecord(id: "602", date: PlanCore.dateAdd(baseWeek, 5), time: "11:30", endTime: "13:00", title: "Farmers Market & Grocery Run", owner: "Mom", kids: ["Maya"], kid: "Maya", location: "Downtown Square", mode: "Drive", color: "#4f46e5"),
                TaskRecord(id: "603", date: PlanCore.dateAdd(baseWeek, 5), time: "14:00", endTime: "16:00", title: "Birthday Party Drop-off & Pickup", owner: "Dad", kids: ["Maya"], kid: "Maya", location: "North Athletic Field", mode: "Drive", color: "#0284c7")
            ],
            6: [
                TaskRecord(id: "701", date: PlanCore.dateAdd(baseWeek, 6), time: "10:00", endTime: "11:30", title: "Sunday Skate Park Session", owner: "Dad", kids: ["Noah"], kid: "Noah", location: "North Athletic Field", mode: "Drive", color: "#0284c7"),
                TaskRecord(id: "702", date: PlanCore.dateAdd(baseWeek, 6), time: "12:00", endTime: "13:30", title: "Family Brunch Transit", owner: "Family", kids: ["Soni", "Maya", "Noah"], kid: "All", location: "Downtown Square", mode: "Drive", color: "#d97706"),
                TaskRecord(id: "703", date: PlanCore.dateAdd(baseWeek, 6), time: "16:00", endTime: "17:15", title: "Swim Team Time Trials", owner: "Mom", kids: ["Soni"], kid: "Soni", location: "Lakeside Sports Complex", mode: "Drive", color: "#4f46e5")
            ]
        ]
    }
}
