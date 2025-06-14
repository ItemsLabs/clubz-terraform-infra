output "postgres_host" {
  value     = digitalocean_database_cluster.fanclash_cluster.host
  sensitive = true
}

output "postgres_port" {
  value = digitalocean_database_cluster.fanclash_cluster.port
}

output "postgres_database_name" {
  value = digitalocean_database_db.fanclash.name
}

output "postgres_root_user" {
  value = digitalocean_database_user.root_user.name
}

output "postgres_root_user_password" {
  value     = digitalocean_database_user.root_user.password
  sensitive = true
}
