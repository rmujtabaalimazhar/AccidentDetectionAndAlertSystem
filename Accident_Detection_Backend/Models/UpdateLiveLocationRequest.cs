using System.ComponentModel.DataAnnotations;

namespace Accident_Detection_Backend.Models
{
    public class UpdateLiveLocationRequest
    {
        [Required]
        public int AccidentId { get; set; }

        // Fallback for snake_case or accident_id
        public int? Accident_Id
        {
            get => AccidentId;
            set { if (value.HasValue && value.Value > 0) AccidentId = value.Value; }
        }

        [Required]
        [Range(-90.0, 90.0)]
        public double Latitude { get; set; }

        [Required]
        [Range(-180.0, 180.0)]
        public double Longitude { get; set; }
    }
}
