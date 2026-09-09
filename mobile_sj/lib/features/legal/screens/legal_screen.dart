import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';

class _Section {
  final String title;
  final String? body;
  final List<String>? bullets;
  final List<(String, String)>? links; // (label, url)
  const _Section({required this.title, this.body, this.bullets, this.links});
}

const _termsSections = [
  _Section(
    title: '1. Acceptance of these terms',
    body: 'By logging into the San Jose GSO Enterprise Asset Management System ("the System"), you agree to these '
        'Terms and Conditions, the Data Privacy Notice, and the User Consent below. If you do not agree, do not use '
        'the System and contact the ICT Division.',
  ),
  _Section(
    title: '2. Restricted system — authorized government use only',
    body: 'This is a private, internal government inventory system operated by the General Services Office (GSO) of '
        'the San Jose Municipal Hall, Batangas. It is not a public service and has no public-facing features. Access '
        'is limited exclusively to GSO and ICT personnel who have been issued an account by an administrator. '
        'Attempting to access, scan, or probe this System without an authorized account is prohibited and may be '
        'referred for investigation and prosecution under the Cybercrime Prevention Act of 2012 (RA 10175) and other '
        'applicable law.',
  ),
  _Section(
    title: '3. Eligibility and account responsibility',
    body: 'Accounts are issued only to GSO/ICT staff, by an administrator, for legitimate government-property-'
        'management duties. You are responsible for every action taken under your account. Do not share your '
        'credentials. Report a lost device, a suspected compromised account, or any suspicious activity to the ICT '
        'Division immediately.',
  ),
  _Section(
    title: '4. Acceptable use',
    body: 'Use the System only for its intended purpose: registering, tracking, and reporting on San Jose LGU '
        'property. Do not enter false or misleading records, attempt to access data outside your role\'s '
        'permissions, copy or export System data for any purpose unrelated to your official duties, or attempt to '
        'circumvent its security controls (including this app\'s screenshot/screen-recording restriction).',
  ),
  _Section(
    title: '5. Ownership of records',
    body: 'All asset, maintenance, disposal, and audit records created in the System are official government '
        'records and property of the San Jose Local Government Unit, subject to Commission on Audit (COA) rules and '
        'the National Archives of the Philippines Act (RA 9470) where applicable. They are not the personal property '
        'of the staff member who created them.',
  ),
  _Section(
    title: '6. Availability and no warranty',
    body: 'The System is provided on an as-available basis for internal government use. The ICT Division makes '
        'reasonable efforts to keep it available and secure but does not warrant uninterrupted operation.',
  ),
  _Section(
    title: '7. Changes to these terms',
    body: 'These Terms, the Data Privacy Notice, and the User Consent may be updated as the System evolves or as '
        'required by law or COA policy. Material changes will be reflected here with an updated date.',
  ),
  _Section(
    title: '8. Governing law',
    body: 'These Terms are governed by the laws of the Republic of the Philippines, including but not limited to RA '
        'No. 10173 (Data Privacy Act of 2012), RA No. 10175 (Cybercrime Prevention Act of 2012), and applicable '
        'Commission on Audit issuances on government property accountability.',
  ),
];

const _privacySections = [
  _Section(
    title: '1. Who we are',
    body: 'This Data Privacy Notice covers the San Jose GSO Enterprise Asset Management System, operated by the '
        'General Services Office of the San Jose Municipal Hall, Batangas. This is a private internal system — it '
        'is not accessible to the public.',
  ),
  _Section(
    title: '2. What information we collect',
    body: '(a) User account info — username, full name, role, office, email; (b) asset records — descriptions, '
        'values, locations, and accountable-person names; (c) activity records — every registration, transfer, '
        'maintenance action, and disposal, with the acting user and timestamp; (d) technical/audit data — IP '
        'address, timestamp, and action type for security-relevant events.',
  ),
  _Section(
    title: '3. Why we collect it',
    body: 'This processing fulfills the GSO\'s mandate to maintain accurate government property records, and COA '
        'requirements for the RPCPPE and related accountability reports. Under RA 10173, this is processing for a '
        'public authority\'s mandate, and you are entitled to be informed of it.',
  ),
  _Section(
    title: '4. Who can access it',
    body: 'Access is restricted to authorized GSO/ICT staff accounts, gated by role. Data is not shared with third '
        'parties except where required by law. The System has no public login, API, or anonymous access.',
  ),
  _Section(
    title: '5. How long we keep it',
    body: 'Records are retained per COA rules on government property and accountability — generally the asset\'s '
        'useful life plus the applicable audit/retention period. Activity logs are kept as long as reasonably '
        'necessary for security and audit purposes.',
  ),
  _Section(
    title: '6. Your responsibilities as a system user',
    body: 'Enter only accurate information; never share your login credentials, since actions under your account '
        'are attributed to you; report any suspected breach or misuse to the ICT Division immediately.',
  ),
  _Section(
    title: '7. Your rights',
    body: 'As a data subject under RA 10173, you have the right to be informed, to access your data, to request '
        'correction, and to lodge a complaint with the National Privacy Commission. Contact the ICT Division for '
        'any request regarding your data.',
  ),
  _Section(
    title: '8. How this System implements the Data Privacy Act',
    bullets: [
      'Passwords are hashed with BCrypt — never stored in readable form.',
      'Sessions use signed JWT tokens in an HttpOnly cookie, invalidated automatically on password change.',
      'Access is role-gated (Admin / Staff), matching the principle of least privilege.',
      'Every create, update, delete, and login is written to an immutable audit trail.',
      'Login attempts are rate-limited and accounts lock out after repeated failures.',
      'Deleting a record archives it (soft delete) rather than erasing the accountability trail.',
      'This app blocks screenshots and screen recording at the OS level (Android FLAG_SECURE) and blurs its '
          'content during active screen mirroring/recording on iOS.',
      'This notice, and your acknowledgment before using the System, satisfy RA 10173\'s transparency requirement.',
    ],
  ),
  _Section(
    title: '9. References',
    links: [
      ('Republic Act No. 10173 — Data Privacy Act of 2012 (Official Gazette)',
          'https://www.officialgazette.gov.ph/2012/08/15/republic-act-no-10173/'),
      ('National Privacy Commission — Data Privacy Act overview', 'https://privacy.gov.ph/data-privacy-act/'),
    ],
  ),
];

const _consentSections = [
  _Section(
    title: '1. What your acknowledgment means',
    body: 'Acknowledging this notice confirms you were informed of what personal data this System processes, why, '
        'and your rights over it, as required by RA 10173. The System records when you acknowledged it.',
  ),
  _Section(
    title: '2. Consent is ongoing',
    body: 'Continuing to use the System after this notice constitutes continued consent to the processing described '
        'in the Privacy Notice tab, for as long as you hold an active account and your use remains within your '
        'official duties.',
  ),
  _Section(
    title: '3. Data you enter about other people',
    body: 'When you record an accountable person\'s name, email, or phone against an asset, you are processing that '
        'person\'s data on the LGU\'s behalf. Only enter such data as part of your official duties.',
  ),
  _Section(
    title: '4. Withdrawing consent / exercising your rights',
    body: 'Because this processing fulfills a public authority\'s mandate, full withdrawal isn\'t possible while you '
        'hold an active account. You may still access, correct, or ask about your own data at any time by '
        'contacting the ICT Division. Deactivating your account on separation stops further collection.',
  ),
  _Section(
    title: '5. Questions or concerns',
    body: 'Direct any question about this notice or your data to the ICT Division, San Jose Municipal Hall. You may '
        'also lodge a complaint with the National Privacy Commission (privacy.gov.ph).',
  ),
];

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Privacy, Terms & Conditions'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Terms & Conditions'),
              Tab(text: 'Privacy Notice'),
              Tab(text: 'User Consent'),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, color: context.colors.textSecondary, height: 1.4),
                        children: const [
                          TextSpan(
                              text: 'This is a private, internal government system ',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: 'for San Jose GSO/ICT staff only. It is not accessible to the public.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SectionList(sections: _termsSections, onOpenLink: (url) => _openLink(context, url)),
                  _SectionList(sections: _privacySections, onOpenLink: (url) => _openLink(context, url)),
                  _SectionList(sections: _consentSections, onOpenLink: (url) => _openLink(context, url)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  final List<_Section> sections;
  final void Function(String url) onOpenLink;
  const _SectionList({required this.sections, required this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: sections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, i) {
        final s = sections[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            if (s.body != null)
              Text(s.body!, style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
            if (s.bullets != null)
              ...s.bullets!.map((b) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: AppTheme.brand, fontSize: 13)),
                        Expanded(
                          child: Text(b, style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.5)),
                        ),
                      ],
                    ),
                  )),
            if (s.links != null)
              ...s.links!.map((l) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      onTap: () => onOpenLink(l.$2),
                      child: Text('${l.$1} ↗',
                          style: const TextStyle(color: AppTheme.brand, fontSize: 13, decoration: TextDecoration.underline)),
                    ),
                  )),
          ],
        );
      },
    );
  }
}
