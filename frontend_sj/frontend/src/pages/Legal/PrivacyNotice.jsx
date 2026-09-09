import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useSelector } from 'react-redux'
import { useTheme } from '../../context/ThemeContext'

const TERMS_SECTIONS = [
  {
    title: '1. Acceptance of these terms',
    body: 'By logging into the San Jose GSO Enterprise Asset Management System ("the System"), you agree to these Terms and Conditions, the Data Privacy Notice, and the User Consent below. If you do not agree, do not use the System and contact the ICT Division.',
  },
  {
    title: '2. Restricted system — authorized government use only',
    body: 'This is a private, internal government inventory system operated by the General Services Office (GSO) of the San Jose Municipal Hall, Batangas. It is not a public service and has no public-facing features. Access is limited exclusively to GSO and ICT personnel who have been issued an account by an administrator. Attempting to access, scan, or probe this System without an authorized account is prohibited and may be referred for investigation and prosecution under the Cybercrime Prevention Act of 2012 (RA 10175) and other applicable law.',
  },
  {
    title: '3. Eligibility and account responsibility',
    body: 'Accounts are issued only to GSO/ICT staff, by an administrator, for legitimate government-property-management duties. You are responsible for every action taken under your account. Do not share your credentials. Report a lost device, a suspected compromised account, or any suspicious activity to the ICT Division immediately.',
  },
  {
    title: '4. Acceptable use',
    body: 'Use the System only for its intended purpose: registering, tracking, and reporting on San Jose LGU property. Do not enter false or misleading records, attempt to access data outside your role\'s permissions, copy or export System data for any purpose unrelated to your official duties, or attempt to circumvent its security controls (including the mobile app\'s screenshot/screen-recording restriction).',
  },
  {
    title: '5. Ownership of records',
    body: 'All asset, maintenance, disposal, and audit records created in the System are official government records and property of the San Jose Local Government Unit, subject to Commission on Audit (COA) rules and the National Archives of the Philippines Act (RA 9470) where applicable. They are not the personal property of the staff member who created them.',
  },
  {
    title: '6. Availability and no warranty',
    body: 'The System is provided on an as-available basis for internal government use. The ICT Division makes reasonable efforts to keep it available and secure but does not warrant uninterrupted operation. Planned maintenance and unplanned outages may occur.',
  },
  {
    title: '7. Changes to these terms',
    body: 'These Terms, the Data Privacy Notice, and the User Consent may be updated as the System evolves or as required by law or COA policy. Material changes will be reflected here with an updated date, and significant changes may require you to re-acknowledge before continuing to use the System.',
  },
  {
    title: '8. Governing law',
    body: 'These Terms are governed by the laws of the Republic of the Philippines, including but not limited to Republic Act No. 10173 (Data Privacy Act of 2012), Republic Act No. 10175 (Cybercrime Prevention Act of 2012), and applicable Commission on Audit issuances on government property accountability.',
  },
]

const PRIVACY_SECTIONS = [
  {
    title: '1. Who we are',
    body: 'This Data Privacy Notice covers the San Jose GSO Enterprise Asset Management System, operated by the General Services Office of the San Jose Municipal Hall, Batangas, for the purpose of tracking municipal government property. This is a private internal system — it is not accessible to the public.',
  },
  {
    title: '2. What information we collect',
    body: 'The system collects and stores: (a) user account information for staff who operate the system — username, full name, role, office assignment, and email address (used only for password-reset delivery); (b) asset records — descriptions, acquisition values, locations, and the names of accountable persons responsible for government property; (c) activity records — every asset registration, transfer, maintenance action, and disposal is logged with the acting user, timestamp, and a description of the action; (d) technical/audit data — IP address, timestamp, and action type for security-relevant events such as logins and record changes.',
  },
  {
    title: '3. Why we collect it',
    body: 'This processing is necessary to comply with the General Services Office\'s mandate to maintain accurate government property records, and with Commission on Audit (COA) requirements for the Report on the Physical Count of Property, Plant and Equipment (RPCPPE) and related accountability reports. Under Republic Act No. 10173 (the Data Privacy Act of 2012), this counts as processing for the fulfillment of a public authority\'s mandate, and you are entitled to be informed of it.',
  },
  {
    title: '4. Who can access it',
    body: 'Access is restricted to authorized GSO and ICT staff accounts, gated by role (Admin or Staff). Every account holder can see their own recorded activity via the Audit Logs module. Data is not shared with third parties except where required by law — for example, COA audits or a lawful government request. The System has no public login, no public API, and no anonymous access of any kind.',
  },
  {
    title: '5. How long we keep it',
    body: 'Asset, maintenance, and disposal records are retained in accordance with COA rules on government property and accountability records, which generally require retention for the useful life of the asset plus the applicable audit/retention period afterward. Account activity logs are retained for as long as reasonably necessary for security and audit purposes.',
  },
  {
    title: '6. Your responsibilities as a system user',
    body: 'If you are a GSO or ICT staff member with an account: enter only accurate information; never share your login credentials with anyone else, since actions taken under your account are attributed to you; and report any suspected data breach, unauthorized access, or misuse to the ICT Division immediately.',
  },
  {
    title: '7. Your rights',
    body: 'As a data subject under RA 10173, you have the right to be informed, to access your own data, to request correction of inaccurate data, and to lodge a complaint with the National Privacy Commission. For any request regarding your personal data held in this system, contact the ICT Division of the San Jose Municipal Hall.',
  },
  {
    title: '8. How this System implements the Data Privacy Act',
    body: null,
    list: [
      'Passwords are never stored in readable form — they are hashed with BCrypt before being saved.',
      'Sessions use signed JWT tokens delivered in an HttpOnly cookie, so they cannot be read or stolen by page scripts, and are automatically invalidated on password change.',
      'Access is role-gated (Admin / Staff) — account management is restricted to Admins, matching the principle of least privilege.',
      'Every create, update, delete, and login action is written to an immutable audit trail, identifying the acting user, timestamp, and action.',
      'Login attempts are rate-limited and accounts lock out after repeated failures, to resist brute-force and credential-stuffing attacks.',
      'Deleting a record archives it (soft delete) rather than erasing it outright, preserving the accountability trail COA requires.',
      'The mobile app blocks screenshots and screen recording at the operating-system level (Android FLAG_SECURE) and blurs its content during active screen mirroring/recording on iOS, since property and personal data must not leave the device as a captured image.',
      'This notice itself, and the acknowledgment you gave before using the System, exist to satisfy RA 10173\'s transparency requirement — you were informed before your data was processed.',
    ],
  },
  {
    title: '9. References',
    body: null,
    links: [
      { label: 'Republic Act No. 10173 — Data Privacy Act of 2012 (Official Gazette)', href: 'https://www.officialgazette.gov.ph/2012/08/15/republic-act-no-10173/' },
      { label: 'National Privacy Commission — Data Privacy Act overview', href: 'https://privacy.gov.ph/data-privacy-act/' },
    ],
  },
]

const CONSENT_SECTIONS = [
  {
    title: '1. What your acknowledgment means',
    body: 'When you clicked "I Understand and Acknowledge" (or do so now), you confirmed you were informed of what personal data this System processes, why, and your rights over it, as required by RA 10173. The System records the date and time of that acknowledgment against your account.',
  },
  {
    title: '2. Consent is ongoing',
    body: 'Continuing to use the System after this notice constitutes continued consent to the processing described in the Privacy Notice tab, for as long as you hold an active account and your use remains within your official duties.',
  },
  {
    title: '3. Data you enter about other people',
    body: 'When you record an accountable person\'s name, email, or phone number against an asset, you are processing that person\'s personal data on the LGU\'s behalf. Only enter such data as part of your official duties, and only from information the accountable person has already provided to the LGU through normal government property-custody procedures.',
  },
  {
    title: '4. Withdrawing consent / exercising your rights',
    body: 'Because this processing fulfills a public authority\'s mandate (COA property accountability), full withdrawal of consent is not possible while you hold an active account — the System cannot function without your account activity being logged. You may still exercise your rights to access, correct, or ask questions about your own data at any time by contacting the ICT Division. Deactivating your account (on separation from GSO/ICT duties) stops further collection.',
  },
  {
    title: '5. Questions or concerns',
    body: 'Direct any question about this notice, your data, or how to exercise your rights under RA 10173 to the ICT Division, San Jose Municipal Hall. You may also lodge a complaint with the National Privacy Commission (privacy.gov.ph) if you believe your rights have been violated.',
  },
]

const TABS = [
  { key: 'terms', label: 'Terms & Conditions', sections: TERMS_SECTIONS },
  { key: 'privacy', label: 'Privacy Notice', sections: PRIVACY_SECTIONS },
  { key: 'consent', label: 'User Consent', sections: CONSENT_SECTIONS },
]

function PrivacyNotice() {
  const navigate = useNavigate()
  const { isDark, toggle } = useTheme()
  const isAuthenticated = useSelector((s) => s.auth.isAuthenticated)
  const [activeTab, setActiveTab] = useState('privacy')

  const current = TABS.find((t) => t.key === activeTab)

  return (
    <div className="min-h-screen bg-white dark:bg-zinc-950">
      <div className="max-w-3xl mx-auto px-6 py-10 sm:py-14">
        {/* Top bar */}
        <div className="flex items-center justify-between mb-10">
          <button
            onClick={() => navigate(isAuthenticated ? '/dashboard' : '/login')}
            className="inline-flex items-center gap-1.5 text-sm font-medium text-slate-500 dark:text-zinc-400 hover:text-slate-800 dark:hover:text-zinc-200 transition-colors duration-150"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fillRule="evenodd" d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z" clipRule="evenodd" />
            </svg>
            Back
          </button>
          <button
            onClick={toggle}
            title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
            aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
            className="p-2.5 rounded-md text-slate-500 dark:text-zinc-400 hover:text-slate-700 dark:hover:text-zinc-200 hover:bg-slate-100 dark:hover:bg-zinc-800 transition-all duration-150"
          >
            {isDark ? (
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fillRule="evenodd" d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z" clipRule="evenodd" />
              </svg>
            ) : (
              <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z" />
              </svg>
            )}
          </button>
        </div>

        {/* Header */}
        <div className="flex items-center gap-4 mb-6">
          <img src="/logo.jpg" alt="San Jose Municipal Hall seal" className="w-12 h-12 rounded-full object-cover ring-2 ring-brand-500/20 flex-shrink-0" />
          <div>
            <p className="text-2xs font-bold text-brand-500 uppercase tracking-[0.15em]">San Jose Municipal Hall · GSO</p>
            <h1 className="text-2xl font-extrabold text-slate-900 dark:text-white tracking-tight">Privacy, Terms &amp; Conditions</h1>
          </div>
        </div>

        <div className="flex items-start gap-2.5 mb-8 px-4 py-3 rounded-lg border border-amber-700/30 bg-amber-500/5">
          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 text-amber-500 flex-shrink-0 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
          <p className="text-xs text-amber-700 dark:text-amber-400 leading-relaxed">
            This is a <strong>private, internal government system</strong> for San Jose GSO/ICT staff only. It is not a public
            service and is not accessible to the public.
          </p>
        </div>

        <p className="text-sm text-slate-500 dark:text-zinc-400 mb-6 leading-relaxed">
          This page explains the terms under which the San Jose GSO Enterprise Asset Management System may be used, what
          personal data it collects and why, and what your acknowledgment/consent covers — in compliance with Republic Act
          No. 10173 (the Data Privacy Act of 2012).
        </p>

        {/* Tabs */}
        <div className="flex gap-1.5 mb-8 border-b border-slate-200 dark:border-zinc-800">
          {TABS.map((t) => (
            <button
              key={t.key}
              onClick={() => setActiveTab(t.key)}
              className={`px-3.5 py-2.5 text-sm font-semibold border-b-2 -mb-px transition-colors duration-150 ${
                activeTab === t.key
                  ? 'border-brand-500 text-brand-600 dark:text-brand-400'
                  : 'border-transparent text-slate-400 dark:text-zinc-500 hover:text-slate-600 dark:hover:text-zinc-300'
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>

        {/* Sections */}
        <div className="space-y-8">
          {current.sections.map((s) => (
            <section key={s.title}>
              <h2 className="text-sm font-bold text-slate-900 dark:text-white mb-1.5">{s.title}</h2>
              {s.body && <p className="text-sm text-slate-600 dark:text-zinc-400 leading-relaxed">{s.body}</p>}
              {s.list && (
                <ul className="space-y-1.5 mt-1">
                  {s.list.map((item, i) => (
                    <li key={i} className="text-sm text-slate-600 dark:text-zinc-400 leading-relaxed flex gap-2">
                      <span className="text-brand-500 flex-shrink-0">•</span>
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              )}
              {s.links && (
                <ul className="space-y-1.5 mt-1">
                  {s.links.map((l) => (
                    <li key={l.href}>
                      <a
                        href={l.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm text-brand-500 hover:text-brand-400 underline underline-offset-2 transition-colors duration-150"
                      >
                        {l.label} ↗
                      </a>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          ))}
        </div>

        <p className="text-xs text-slate-400 dark:text-zinc-600 mt-12 pt-6 border-t border-slate-100 dark:border-zinc-800">
          Last updated {new Date().toLocaleDateString('en-PH', { year: 'numeric', month: 'long', day: 'numeric' })}.
          Questions about this notice or your data should be directed to the ICT Division, San Jose Municipal Hall.
        </p>
      </div>
    </div>
  )
}

export default PrivacyNotice
