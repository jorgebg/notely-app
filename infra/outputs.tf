output "url" {
  description = "Address of the page"
  value       = module.web.uri
}

output "api_url" {
  description = "Address of the API"
  value       = module.api.uri
}
