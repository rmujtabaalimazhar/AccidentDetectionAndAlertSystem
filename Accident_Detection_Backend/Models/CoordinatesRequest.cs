using System.ComponentModel.DataAnnotations;

namespace Accident_Detection_Backend.Models
{
    public class CoordinatesRequest
    {
        [Required]
        [Range(-90, 90)]
        public double Latitude  { get; set; }

        [Required]
        [Range(-180, 180)]
        public double Longitude { get; set; }
    }
}