// Gmail relay for EmailService (see MAIL_RELAY_URL / MAIL_RELAY_SECRET).
// Render's free tier blocks SMTP, so the backend POSTs mail here over HTTPS and
// this script sends it from the Google account that deployed it.
//
// Setup: Project Settings > Script Properties > add RELAY_SECRET (same value as
// MAIL_RELAY_SECRET on Render). Deploy > New deployment > Web app,
// "Execute as: Me", "Who has access: Anyone". Copy the /exec URL to MAIL_RELAY_URL.
// Consumer Gmail accounts can send about 100 emails a day this way.

function doPost(e) {
  var secret = PropertiesService.getScriptProperties().getProperty('RELAY_SECRET');
  var req;
  try {
    req = JSON.parse(e.postData.contents);
  } catch (err) {
    return reply({ ok: false, error: 'bad json' });
  }
  if (!secret || req.secret !== secret) {
    return reply({ ok: false, error: 'unauthorized' });
  }
  if (!req.to || !req.subject) {
    return reply({ ok: false, error: 'missing to/subject' });
  }

  MailApp.sendEmail({
    to: req.to,
    subject: req.subject,
    htmlBody: req.html || '',
    name: req.fromName || 'San Jose GSO Enterprise Asset Management System'
  });
  return reply({ ok: true });
}

function reply(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

// Run once from the editor to grant the "send email as you" permission.
function authorize() {
  MailApp.getRemainingDailyQuota();
}
