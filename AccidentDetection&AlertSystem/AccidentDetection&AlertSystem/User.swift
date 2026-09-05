
import Foundation

struct User: Codable {
    var uid: String
    var name: String
    var password: String
    var role: String
    var contactNo: String
    
    enum CodingKeys: String, CodingKey {
        case uid = "Uid"
        case name = "Name"
        case password = "Password"
        case role = "Role"
        case contactNo = "Contact_No"
    }
}

