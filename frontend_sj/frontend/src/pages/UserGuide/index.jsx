import { Link } from 'react-router-dom'
import { useSelector } from 'react-redux'
import MainLayout from '../../components/layout/MainLayout'
import { roleLabel } from '../../utils/roles'

// Docs > User Guide, styled like the first-login "Before you start" guide: short numbered
// points. Each role gets its own guide, and the page shows the one for the signed-in account.

const NUMBERS = { term: 'Property No. and PAR No.', desc: 'Property No.: year, category code, serial, office code (2024-05030-012-1011). PAR No.: acquisition month and serial (2015-01:0001). Each asset has its own.' }
const CONDITION = { term: 'Condition', desc: 'New, Good, Serviceable, Repairable or Unserviceable. Repairable puts the asset under maintenance; Unserviceable puts it up for disposal.' }
const NOTIFICATIONS = { term: 'Notifications', desc: 'The bell at the top right lists what needs you. Click one to open the records it is about.' }
const MOBILE = { term: 'Mobile app', desc: 'Get the Android app from Docs > Mobile App. It scans QR stickers, takes repair photos and works offline.' }
const ACCOUNT = { term: 'Your account', desc: 'Click your avatar for My Account (password, photo, 2-step verification) and Appearance. You are signed out after 15 minutes idle.', to: '/my-account', link: 'My Account' }
const REPORTS_SCOPED = { term: 'Reports', desc: 'Print or download RPCPPE, condition, PAR, property card, IIRUP and more for the offices you can see.', to: '/reports', link: 'Reports' }

// Staff and Admin-Staff work the same way; they differ in what they can see.
const requestGuide = (seesAll) => [
  {
    title: 'The basics',
    items: [
      seesAll
        ? { term: 'What you can see', desc: 'Every office\'s assets and every staff request. You file requests like staff; an administrator approves them.' }
        : { term: 'What you can see', desc: 'Only the assets of the offices assigned to you. Ask an administrator if an office is missing.' },
      NUMBERS,
      CONDITION,
      { term: 'Requests', desc: 'Maintenance, disposal and transfers you file wait for an administrator. Nothing changes on the asset until it is approved; a rejection comes with a reason.' },
    ],
  },
  {
    title: 'Everyday tasks',
    items: [
      { term: 'Find an asset', desc: 'Search or filter on Assets, or scan its QR sticker on Transfer Asset.', to: '/assets', link: 'Assets' },
      { term: 'Update an asset', desc: 'Open it and press Edit. A change of condition to Repairable or Unserviceable is sent as a request.' },
      { term: 'Transfer an asset', desc: 'On Transfer Asset, find the asset, pick the new office and person, and send. Follow it under My Requests.', to: '/transfer', link: 'Transfer Asset' },
      { term: 'Maintenance', desc: 'Once your request is approved you can edit the record. Add a before and an after photo to mark it Completed.', to: '/maintenance', link: 'Maintenance' },
      { term: 'Disposal', desc: 'Only Repairable or Unserviceable assets. Give the reason and the method (Sale, Transfer, Destruction or Others).', to: '/disposal', link: 'Disposal' },
      REPORTS_SCOPED,
    ],
  },
  {
    title: 'Good to know',
    items: [NOTIFICATIONS, MOBILE, ACCOUNT],
  },
]

const GUIDES = {
  ADMIN: {
    intro: 'You approve requests, keep the records right and set up the system.',
    groups: [
      {
        title: 'The basics',
        items: [
          { term: 'Roles', desc: 'GSO Staff see their own offices; Admin-Staff see everything. Both file requests. Only administrators approve, add, import and delete.' },
          NUMBERS,
          CONDITION,
        ],
      },
      {
        title: 'Everyday tasks',
        items: [
          { term: 'Approve requests', desc: 'The bell shows requests waiting. Approve or reject them on Asset History > Requests, Maintenance, Disposal or Transfer Asset > Requests. A rejection needs a reason.', to: '/asset-history?view=requests', link: 'Requests' },
          { term: 'Add assets', desc: 'Add one or import from Excel on Assets. A PAR No. is required; the Property No. is made from the category and office codes.', to: '/assets', link: 'Assets' },
          { term: 'Transfer an asset', desc: 'Your transfers apply at once. If the end user changes, type the new PAR No.; print the return slip and PAR from the asset\'s PARs & Return Slips tab.', to: '/transfer', link: 'Transfer Asset' },
          { term: 'Maintenance and disposal', desc: 'A repair needs a before and an after photo to be Completed. A disposal goes Pending, Approved, Completed; the asset stays listed as Disposed.' },
          { term: 'Reports and planning', desc: 'Reports prints the RPCPPE, depreciation, replacement forecast and more. Home > Budget & Planning shows what is due for replacement.', to: '/reports', link: 'Reports' },
        ],
      },
      {
        title: 'Setting up',
        items: [
          { term: 'Offices and categories', desc: 'Set each one\'s property code. Categories also hold the useful life in years and their list of articles.', to: '/categories', link: 'Categories' },
          { term: 'Personnel and accounts', desc: 'Assign each person\'s office on Personnel. Accounts are deactivated, never deleted; hand their assets to someone else first.', to: '/personnel', link: 'Personnel' },
          { term: 'Audit Logs and Recovery', desc: 'Audit Logs records every action. Deleted assets and records wait in Recovery to be restored.', to: '/deleted-records', link: 'Recovery' },
          NOTIFICATIONS,
          MOBILE,
        ],
      },
    ],
  },
  ADMIN_STAFF: { intro: 'You see the whole inventory and keep it up to date; an administrator approves your requests.', groups: requestGuide(true) },
  STAFF: { intro: 'You keep your offices\' assets up to date; an administrator approves your requests.', groups: requestGuide(false) },
}

function UserGuide() {
  const role = useSelector((s) => s.auth.user?.role)
  const guide = GUIDES[role] || GUIDES.STAFF
  let n = 0

  return (
    <MainLayout>
      <div className="max-w-2xl mx-auto bg-white dark:bg-zinc-900 border border-slate-200 dark:border-zinc-800 rounded-xl">
        <div className="px-6 sm:px-7 pt-6 pb-5 border-b border-slate-200 dark:border-zinc-800">
          <p className="text-2xs font-semibold text-brand-500 uppercase tracking-widest mb-1.5">User guide</p>
          <h2 className="text-lg font-bold text-slate-900 dark:text-white leading-snug">For {roleLabel(role)}</h2>
          <p className="text-sm text-slate-500 dark:text-zinc-400 mt-1">{guide.intro}</p>
        </div>

        {guide.groups.map((g) => (
          <section key={g.title} aria-label={g.title} className="px-6 sm:px-7 py-5 border-b last:border-b-0 border-slate-200 dark:border-zinc-800">
            <h3 className="text-2xs font-semibold text-slate-500 dark:text-zinc-400 uppercase tracking-widest mb-4">{g.title}</h3>
            <ol className="space-y-4">
              {g.items.map((c) => {
                n += 1
                return (
                  <li key={c.term} className="flex items-start gap-4">
                    <span className="w-6 h-6 rounded-full bg-brand-500/10 text-brand-600 dark:text-brand-400 text-xs font-bold flex items-center justify-center flex-shrink-0 mt-px select-none">
                      {n}
                    </span>
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-slate-800 dark:text-zinc-100 leading-snug">{c.term}</p>
                      <p className="text-xs text-slate-500 dark:text-zinc-400 mt-1 leading-relaxed">
                        {c.desc}
                        {c.to && <> <Link to={c.to} className="font-medium text-brand-700 dark:text-brand-300 hover:underline whitespace-nowrap">Open {c.link}</Link></>}
                      </p>
                    </div>
                  </li>
                )
              })}
            </ol>
          </section>
        ))}
      </div>
    </MainLayout>
  )
}

export default UserGuide
