
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json.Serialization; // 👈 Add this using statement!
using Microsoft.EntityFrameworkCore;

namespace Accident_Detection_Backend.Models
{
    [Table("Nodes")]
    [PrimaryKey(nameof(Node_Id), nameof(Category_Id))]
    public class Nodes
    {
        [DatabaseGenerated(DatabaseGeneratedOption.None)]
        public int Node_Id { get; set; }

        [Required]
        public int Category_Id { get; set; }

        [StringLength(100)]
        public string? Node_Position { get; set; }

        [Column("Force_Value", TypeName = "decimal(10,2)")]
        public decimal? Force { get; set; }

        // 👇 FIX: Add JsonIgnore and make it nullable (Category?)
        [JsonIgnore]
        [ForeignKey("Category_Id")]
        public virtual Category? Category { get; set; } 
    }
}
//dotnet run --urls "http://0.0.0.0:5192"



