using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Accident_Detection_Backend.Models
{
   [Table("User")]
    public class User
    {
        [Key]
        [StringLength(255)]
        public string Uid { get; set; } = null!;

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = null!;

        [Required]
        [StringLength(255)]
        public string Password { get; set; } = null!;

        [Required]
        [StringLength(50)]
        public string Role { get; set; } = "User";

        [StringLength(20)]
        public string? Contact_No { get; set; }

        // Navigation Property
        public ICollection<Car> Cars { get; set; } = new List<Car>();
    }
}