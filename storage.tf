resource "opentelekomcloud_obs_bucket" "ollama_models" {
  bucket = "ollama-models-eu-de"
  acl    = "private"
}
