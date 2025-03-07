function Send-TeamsNotification {
  param (
      [string]$Message = "No message provided",
      [string]$Title = "AVM Package Processing Report",
      [string]$Color = "0078D7" # Default blue
  )

  if ([string]::IsNullOrEmpty($TeamsWebhookUrl)) {
      Write-Log "Teams webhook URL not provided. Skipping notification." -Level "WARNING"
      return
  }

  try {
      $payload = @{
          "@type"      = "MessageCard"
          "@context"   = "http://schema.org/extensions"
          "themeColor" = $Color
          "title"      = $Title
          "text"       = $Message
      }

      $body = ConvertTo-Json -InputObject $payload -Depth 4

      Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -Body $body -ContentType 'application/json'
      Write-Log "Teams notification sent successfully" -Level "SUCCESS"
  }
  catch {
      Write-Log "Failed to send Teams notification: $_" -Level "ERROR"
  }
}