// using Microsoft.EntityFrameworkCore;

// namespace Accident_Detection_Backend.Models
// {
//     public class AppDbContext : DbContext
//     {
//         public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
//         {
//         }

//         public DbSet<User> Users { get; set; }
//         public DbSet<Category> Categories { get; set; }
//         public DbSet<Car> Cars { get; set; }
//         public DbSet<Nodes> Nodes { get; set; }
//         public DbSet<Accident> Accidents { get; set; }
        
//         protected override void OnModelCreating(ModelBuilder modelBuilder)
//         {
//             base.OnModelCreating(modelBuilder);
            
//             // Enforce Registration_No is UNIQUE
//             modelBuilder.Entity<Car>()
//                 .HasIndex(c => c.Registration_No)
//                 .IsUnique();
//         }
//     }
// }

using Microsoft.EntityFrameworkCore;

namespace Accident_Detection_Backend.Models
{
    public class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
        {
        }

        public DbSet<User> Users { get; set; }
        public DbSet<Category> Categories { get; set; }
        public DbSet<Car> Cars { get; set; }
        public DbSet<Nodes> Nodes { get; set; }
        public DbSet<Accident> Accidents { get; set; }
        public DbSet<NodeConnection> NodeConnections { get; set; }
        public DbSet<FamilyMembers> FamilyMembers { get; set; }
        public DbSet<Rescue> Rescues { get; set; }
        public DbSet<Alert> Alerts { get; set; }
        public DbSet<DeviceToken> DeviceTokens { get; set; }
        
        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);
            
            // Enforce Registration_No is UNIQUE
            modelBuilder.Entity<Car>()
                .HasIndex(c => c.Registration_No)
                .IsUnique();

            // 👇 Define the composite Primary Key for the Nodes table
            modelBuilder.Entity<Nodes>()
                .HasKey(n => new { n.Node_Id, n.Category_Id });

            // Composite Primary Key for FamilyMembers (Uid, Guardian_Id)
            modelBuilder.Entity<FamilyMembers>()
                .HasKey(f => new { f.Uid, f.Guardian_Id });

            modelBuilder.Entity<FamilyMembers>()
                .HasIndex(f => f.Family_Id)
                .IsUnique();
        }
    }
}
