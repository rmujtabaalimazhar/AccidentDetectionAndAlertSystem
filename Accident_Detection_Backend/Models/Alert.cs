using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization;

namespace Accident_Detection_Backend.Models
{
    [Table("Alert")]
    public class Alert
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Alert_Id { get; set; }

        [Required]
        public int Accident_Id { get; set; }

        [Column("Time")]
        public DateTime Time { get; set; } = DateTime.Now;

        [Column("Status")]
        public bool Status { get; set; } = false;

        // Navigation Property
        [ForeignKey("Accident_Id")]
        [JsonIgnore]
        public virtual Accident? Accident { get; set; }
    }
}

/*
1. User logs into iPhone as Guardian or Rescue.
   └── Phone sends device token & user ID to backend -> saved in database.

2. User closes / minimizes the app.

3. Car crashes -> Accident data posted to DetectAccident/ImpactCalculation.
   ├── Accident & Alert saved in database.
   ├── PushNotificationService finds guardians & nearest rescue.
   └── Notification payload prepared and dispatched.

4. Phone receives the notification (via APNs or background check).
   └── Apple UNUserNotificationCenter sounds alarm and drops down banner:
       "🚨 EMERGENCY: Family Accident Alert!"

5. User taps the banner on their phone.
   └── App opens directly to the accident dispatch / map view!








   ########################
   ########
   Here is the complete, step-by-step breakdown of how the notification system works in simple words, including every file created and modified.

How It Works In Simple Words
Before this change: Alerts only existed inside the database. A guardian or rescue team had to open the app, go to the alerts screen, and click refresh to see anything. If the app was closed, they had no idea an accident had occurred.

After this change:

When a user logs in (as Guardian or Rescue), the app registers their phone with the backend.
When an accident happens, the backend identifies who the guardians are and which rescue unit is closest.
Even if the app is closed, minimized, or the phone screen is locked, the system triggers a high-priority emergency banner notification with sound.
When the user taps that notification, the app immediately opens up and shows the accident details and live map.
Summary of Files (Total: 10 Files)
5 Backend Files (2 created, 3 modified)
5 iOS App Files (2 created, 3 modified)
Part 1: Backend (Accident_Detection_Backend)
1. 

Models/DeviceToken.cs
 (Created)
What it does: Represents a database table (DeviceTokens) that stores phone device tokens linked to user IDs (e.g., guardian@example.com or Rescue ID 1). This lets the backend know which phone belongs to which user.
2. 

Models/AppDbContext.cs
 (Modified)
What it does: Added public DbSet<DeviceToken> DeviceTokens { get; set; } so Entity Framework can save and query device tokens in the database.
3. 

Services/PushNotificationService.cs
 (Created)
What it does: This is the notification engine:
When an accident happens, it looks up the driver's vehicle.
It finds all guardians connected to that driver in FamilyMembers.
It finds the nearest rescue unit by calculating GPS distance.
It prepares emergency notification payloads (title, body, sound, crash location, impact force) for those specific users.
4. 

Controllers/NotificationsController.cs
 (Created)
What it does: Provides API endpoints:
POST /api/Notifications/RegisterToken: Called by the phone upon login to register its push token.
GET /api/Notifications/CheckPending: Fast endpoint used by the phone's background task to check for new unread alerts.
5. 

Controllers/DetectAccident.cs
 (Modified)
What it does: In ImpactCalculation, right after saving the new Alert to the database, it immediately calls _pushService.SendAccidentAlertNotificationAsync(...) to trigger notifications to guardians and rescue teams.
6. 

Program.cs
 (Modified)
What it does: Registered PushNotificationService in the ASP.NET dependency injection container so DetectAccidentController can use it.
Part 2: iOS App (AccidentDetection&AlertSystem)
1. 

NotificationManager.swift
 (Created)
What it does: The central brain of notifications on the phone:
Asks the user for notification permissions (.alert, .sound, .badge).
Sets up UNUserNotificationCenterDelegate so popups show banner alerts with emergency sound both when the app is in the background and when in the foreground.
Saves the active user role and ID to UserDefaults.
Sends the phone's device token to the backend API (/api/Notifications/RegisterToken).
Runs background checks (checkForNewAlerts) and fires a native Apple notification banner when an accident is detected.
When the user taps the popup banner, it deep-links directly to that accident.
2. 

AccidentDetection_AlertSystemApp.swift
 (Modified)
What it does: Connected an AppDelegate to the SwiftUI app lifecycle. This handles background app wakeups (BGTaskScheduler), Apple Push Notifications (APNs), and passes the notification manager to all views.
3. 

AccidentDetection-AlertSystem-Info.plist
 (Modified)
What it does: Tells iOS that this app is allowed to run tasks while minimized:
Added UIBackgroundModes: fetch, remote-notification, and processing.
Added BGTaskSchedulerPermittedIdentifiers: com.fyp.accidentdetection.alertcheck.
4. 

Login.swift
 (Modified)
What it does: Whenever a user or rescue team logs in successfully, it calls NotificationManager.shared.setUserSession(role: ..., identifier: ...) so the phone immediately starts monitoring for emergency alerts for that specific account.
5. 

ContentView.swift
 (Modified)
What it does:
Automatically restores the user's session if they reopen the app.
Listens for notification taps and immediately opens the emergency alert screen or popup sheet.
Cleans up notification sessions when the user logs out.
Step-by-Step Flow (What happens during an accident):
text
1. User logs into iPhone as Guardian or Rescue.
   └── Phone sends device token & user ID to backend -> saved in database.
2. User closes / minimizes the app.
3. Car crashes -> Accident data posted to DetectAccident/ImpactCalculation.
   ├── Accident & Alert saved in database.
   ├── PushNotificationService finds guardians & nearest rescue.
   └── Notification payload prepared and dispatched.
4. Phone receives the notification (via APNs or background check).
   └── Apple UNUserNotificationCenter sounds alarm and drops down banner:
       "🚨 EMERGENCY: Family Accident Alert!"
5. User taps the banner on their phone.
   └── App opens directly to the accident dispatch / map view!

*/