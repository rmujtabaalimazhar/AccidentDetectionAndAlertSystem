import Foundation

struct Car: Codable, Identifiable {
    var id: Int { carId ?? 0 }
    var carId: Int?
    var registrationNo: String
    var make: String?
    var uid: String
    var categoryId: Int
    
    init(registrationNo: String, make: String?, uid: String, categoryId: Int) {
        self.registrationNo = registrationNo
        self.make = make
        self.uid = uid
        self.categoryId = categoryId
    }
    
    enum CodingKeys: String, CodingKey {
        case carId, car_Id, Car_Id
        case registrationNo, registration_No, Registration_No
        case make, Make
        case uid, Uid
        case categoryId, category_Id, Category_Id
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        carId = try container.decodeIfPresent(Int.self, forKey: .carId) ??
                container.decodeIfPresent(Int.self, forKey: .car_Id) ??
                container.decodeIfPresent(Int.self, forKey: .Car_Id)
        
        registrationNo = try container.decodeIfPresent(String.self, forKey: .registrationNo) ??
                         container.decodeIfPresent(String.self, forKey: .registration_No) ??
                         container.decodeIfPresent(String.self, forKey: .Registration_No) ?? ""
        
        make = try container.decodeIfPresent(String.self, forKey: .make) ??
               container.decodeIfPresent(String.self, forKey: .Make)
        
        uid = try container.decodeIfPresent(String.self, forKey: .uid) ??
              container.decodeIfPresent(String.self, forKey: .Uid) ?? ""
        
        categoryId = try container.decodeIfPresent(Int.self, forKey: .categoryId) ??
                     container.decodeIfPresent(Int.self, forKey: .category_Id) ??
                     container.decodeIfPresent(Int.self, forKey: .Category_Id) ?? 1
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(carId, forKey: .Car_Id)
        try container.encode(registrationNo, forKey: .Registration_No)
        try container.encodeIfPresent(make, forKey: .Make)
        try container.encode(uid, forKey: .Uid)
        try container.encode(categoryId, forKey: .Category_Id)
    }
}
