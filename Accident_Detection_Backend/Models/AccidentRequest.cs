// using System.ComponentModel.DataAnnotations;

// namespace Accident_Detection_Backend.Models
// {
//     public class AccidentRequest
//     {
//         [Required]
//         public int CarId { get; set; }

//         public string? AccidentType { get; set; }

//         public string? ImpactSide { get; set; }

//         public double Acceleration { get; set; }

//         // Gyroscope data
//         public double GyroX { get; set; }
//         public double GyroY { get; set; }


//         public double GyroZ { get; set; }
//         // Location info
//         public string? Location { get; set; }

//         public double Latitude { get; set; }
//         public double Longitude { get; set; }
//     }
// }

using System.ComponentModel.DataAnnotations;

namespace Accident_Detection_Backend.Models
{
    public class AccidentRequest
    {
        [Required]
        public int CarId { get; set; }

        public string? AccidentType { get; set; }
        public string? ImpactSide { get; set; }

        // Linear Acceleration Vectors
        public double Acceleration { get; set; }
        public double AccelX { get; set; }
        public double AccelY { get; set; }
        public double AccelZ { get; set; }

        // Gyroscope data
        public double GyroX { get; set; }
        public double GyroY { get; set; }
        public double GyroZ { get; set; }

        // Location info
        public string? Location { get; set; }
        public double Latitude { get; set; }
        public double Longitude { get; set; }
    }
}