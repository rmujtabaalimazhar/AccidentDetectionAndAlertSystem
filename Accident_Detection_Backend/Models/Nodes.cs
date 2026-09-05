
// // using System.ComponentModel.DataAnnotations;
// // using System.ComponentModel.DataAnnotations.Schema;
// // using Microsoft.EntityFrameworkCore; // 👈 You need this using statement for PrimaryKey

// // namespace Accident_Detection_Backend.Models
// // {
// //     [Table("Nodes")]
// //     // 👈 This tells Entity Framework about your composite primary key
// //     [PrimaryKey(nameof(Node_Id), nameof(Category_Id))]
// //     public class Nodes
// //     {
// //         // NO [Key] attribute goes here anymore
// //         [DatabaseGenerated(DatabaseGeneratedOption.None)]
// //         public int Node_Id { get; set; }

// //         [Required]
// //         public int Category_Id { get; set; }

// //         [StringLength(100)]
// //         public string? Node_Position { get; set; }

// //         [Column(TypeName = "decimal(10,2)")]
// //         public decimal? Force { get; set; }

// //         // Navigation Property
// //         [ForeignKey("Category_Id")]
// //         public Category Category { get; set; } = null!;
// //     }
// // }


// using System.ComponentModel.DataAnnotations;
// using System.ComponentModel.DataAnnotations.Schema;
// using Microsoft.EntityFrameworkCore;

// namespace Accident_Detection_Backend.Models
// {
//     [Table("Nodes")]
//     [PrimaryKey(nameof(Node_Id), nameof(Category_Id))]
//     public class Nodes
//     {
//         [DatabaseGenerated(DatabaseGeneratedOption.None)]
//         public int Node_Id { get; set; }

//         [Required]
//         public int Category_Id { get; set; }

//         [StringLength(100)]
//         public string? Node_Position { get; set; }

//         // 👇 FIX: Add "Force_Value" here to match your database column
//         [Column("Force_Value", TypeName = "decimal(10,2)")]
//         public decimal? Force { get; set; }

//         [ForeignKey("Category_Id")]
//         public Category Category { get; set; } = null!;
//     }
// }

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