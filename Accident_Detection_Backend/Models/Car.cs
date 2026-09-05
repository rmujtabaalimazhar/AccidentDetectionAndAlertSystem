using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization; // <-- Make sure this is here

namespace Accident_Detection_Backend.Models
{
    [Table("Car")]  // <--- THIS FIXES THE ERROR! It tells EF to use 'Car' instead of 'Cars'
    public class Car
    {
        [Key]
        public int Car_Id { get; set; }

        [Required]
        [MaxLength(50)]
        public string Registration_No { get; set; } = string.Empty;

        [MaxLength(100)]
        public string? Make { get; set; }

        [Required]
        [MaxLength(255)]
        public string Uid { get; set; } = string.Empty;

              [Required]
        public int Category_Id { get; set; }

        // --- ADD THESE ATTRIBUTES ---
        
        [JsonIgnore]
        [ForeignKey("Uid")] // Tells EF to use the 'Uid' column
        public virtual User? User { get; set; }
        
        [JsonIgnore]
        [ForeignKey("Category_Id")] // Tells EF to use the 'Category_Id' column
        public virtual Category? Category { get; set; }

        
    }
}
      