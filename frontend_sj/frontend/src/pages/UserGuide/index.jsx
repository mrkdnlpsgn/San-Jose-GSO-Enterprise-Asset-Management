import { Link } from 'react-router-dom'
import { useSelector } from 'react-redux'
import MainLayout from '../../components/layout/MainLayout'

// Docs > User Guide: how the system works today, module by module. Parts only an administrator
// can do are marked; staff still see them so they know who to ask.

const CARD = 'bg-white dark:bg-zinc-900 rounded-xl border border-slate-200 dark:border-zinc-800'

function AdminOnly() {
  return (
    <span className="ml-2 align-middle inline-flex px-2 py-0.5 rounded-full text-2xs font-semibold bg-slate-500/10 text-slate-700 dark:text-zinc-300 ring-1 ring-slate-500/30">
      Admins only
    </span>
  )
}

// Inline link to a page of the system
function To({ to, children }) {
  return <Link to={to} className="font-medium text-brand-700 dark:text-brand-300 underline underline-offset-2 hover:no-underline">{children}</Link>
}

function Code({ children }) {
  return <code className="font-mono text-[0.8125rem] px-1 py-0.5 rounded bg-slate-100 dark:bg-zinc-800 text-slate-800 dark:text-zinc-200">{children}</code>
}

function Steps({ items }) {
  return (
    <ol className="space-y-1.5 list-decimal pl-5 marker:text-slate-400 dark:marker:text-zinc-500">
      {items.map((s, i) => <li key={i}>{s}</li>)}
    </ol>
  )
}

function Bullets({ items }) {
  return (
    <ul className="space-y-1.5 list-disc pl-5 marker:text-slate-400 dark:marker:text-zinc-500">
      {items.map((s, i) => <li key={i}>{s}</li>)}
    </ul>
  )
}

// term / meaning table rows
function Terms({ rows }) {
  return (
    <dl className="divide-y divide-slate-100 dark:divide-zinc-800 rounded-lg border border-slate-200 dark:border-zinc-800">
      {rows.map(([term, desc]) => (
        <div key={term} className="grid grid-cols-1 sm:grid-cols-[11rem_1fr] gap-x-4 gap-y-0.5 px-4 py-2.5">
          <dt className="font-semibold text-slate-800 dark:text-zinc-100">{term}</dt>
          <dd>{desc}</dd>
        </div>
      ))}
    </dl>
  )
}

function Sub({ children }) {
  return <h3 className="text-sm font-semibold text-slate-900 dark:text-white mt-4 mb-1.5">{children}</h3>
}

const SECTIONS = [
  {
    id: 'start',
    title: 'Signing in and your account',
    body: <>
      <Bullets items={[
        <>Sign in with your <strong>username</strong> and password. Accounts are made by an administrator; there is no self sign-up.</>,
        <>If 2-step verification is on, a 6-digit code is emailed to you after the password. You can turn it on or off in <To to="/my-account">My Account</To>.</>,
        <>Forgot your password? Use <strong>Forgot password</strong> on the sign-in page; a reset code goes to the email on your account.</>,
        <>The first time you sign in you are asked to read and accept the <To to="/privacy">Privacy &amp; Terms</To>.</>,
        <>After 14 minutes without activity you are warned, and at 15 minutes you are signed out.</>,
        <>The avatar at the top right opens <strong>My Account</strong> (name, email, photo, password, 2-step verification), <strong>Appearance</strong> (light or dark theme and text size) and <strong>Sign Out</strong>.</>,
      ]} />
      <Sub>Roles</Sub>
      <Terms rows={[
        ['Administrator', 'Everything: adds, imports and deletes assets, applies transfers directly, approves or rejects requests, and manages offices, categories, personnel, accounts, audit logs and recovery.'],
        ['Admin-Staff', 'Sees every office\'s assets and every staff request, but works like staff: changes go to an administrator as requests, and it cannot approve or reject.'],
        ['GSO Staff', 'Sees only the assets of the offices assigned to them on the Personnel page. Can edit those assets and change their status; maintenance, disposal and transfers go to an administrator as requests.'],
      ]} />
    </>,
  },
  {
    id: 'terms',
    title: 'Key terms',
    body: <Terms rows={[
      ['Property No.', <>The asset's unique number: <strong>year acquired, category code, serial, office code</strong>, for example <Code>2024-05030-012-1011</Code>. It is made automatically from the category's and office's codes. When an asset moves to another office, the office code at the end changes and the QR sticker is re-signed.</>],
      ['PAR No.', <>Property Acknowledgment Receipt number, written <Code>YYYY-MM:SERIAL</Code> and starting with the acquisition month, for example <Code>2015-01:0001</Code>. Each asset has its own; a PAR number can't be reused. Required for new assets.</>],
      ['Accountable person', 'The end user who signed the PAR and answers for the asset. Changing this person through a transfer makes a Property Return Slip and a new PAR.'],
      ['Article', 'The kind of item within a category, for example ICT Equipment > Laptop. Each category has its own list.'],
      ['Condition', <>How the asset is: <strong>New</strong>, <strong>Good</strong>, <strong>Serviceable</strong>, <strong>Repairable</strong> or <strong>Unserviceable</strong>. New assets age to Good and then Serviceable on their own over time.</>],
      ['Status', <><strong>Assigned</strong>, <strong>Transferred</strong>, <strong>Under maintenance</strong> or <strong>Disposed</strong>. Status follows the condition and the Transfer page; it isn't typed in.</>],
      ['Request', 'A maintenance, disposal or transfer filed by staff or Admin-Staff. Nothing changes on the asset until an administrator approves it; a rejection comes with a reason.'],
    ]} />,
  },
  {
    id: 'home',
    title: 'Home',
    body: <Bullets items={[
      'The top row shows assets in use, their value (book value after depreciation for administrators), and how many are under repair or up for disposal. Click a figure to open those assets.',
      'A bar shows the assets by condition, followed by breakdowns by office and by category; each one opens the matching assets.',
      <><strong>Budget &amp; Planning</strong> <AdminOnly />: assets due for replacement now and in the coming years, the estimated cost, and a summary in plain words.</>,
      'Staff see the same page for their own offices. Requests and asset problems that need you are in the notification bell.',
    ]} />,
  },
  {
    id: 'assets',
    title: 'Assets',
    body: <>
      <Bullets items={[
        'Search by property number, PAR number, description or person. Filter by category, status, condition and office (More filters).',
        'Click a row to open its details. The tabs are Details, Lifecycle (its history), Specifications, AI Insight (a recommendation such as Maintain, Repair or Review for disposal), Maintenance, and PARs & Return Slips (print the PAR and return slips).',
        <>From the details you can edit the asset, print its QR sticker, or start a transfer.</>,
        'Download Excel exports the list as shown. Export QR codes prints stickers for the assets you tick.',
        <>Add an asset or Import from Excel <AdminOnly />. A new asset needs a PAR No.; its property number is made from the category and office codes.</>,
        <>Delete <AdminOnly />: the asset moves to Recovery and can be restored.</>,
      ]} />
      <Sub>Changing the condition</Sub>
      <Bullets items={[
        'Setting an asset to Repairable puts it under maintenance and opens a maintenance record.',
        'Setting it to Unserviceable puts it up for disposal and opens a disposal record.',
        'For staff, either change is sent as a request; the asset keeps its condition until an administrator approves.',
      ]} />
    </>,
  },
  {
    id: 'transfer',
    title: 'Transfer Asset',
    body: <>
      <Sub>Transfer tab</Sub>
      <Steps items={[
        'Press Scan QR Code (phones open a full-screen scanner, computers use the webcam) or type a property or PAR number.',
        'A scanned sticker is checked: Genuine, Old sticker (print a new one), or Failed verification (report it to the GSO).',
        'Choose the office it moves to and, if it changes hands, the new accountable person. Add a reason if you like.',
        <>If the accountable person changes, a <strong>Property Return Slip</strong> is made for the old one and the new one receives a <strong>new PAR</strong>; administrators type the new PAR No. Print both from the asset's PARs &amp; Return Slips tab.</>,
        'An administrator\'s transfer takes effect at once. Staff and Admin-Staff send a request instead.',
      ]} />
      <Sub>Requests tab</Sub>
      <Bullets items={[
        'Lists transfer requests with their status: Awaiting approval, Approved or Rejected. Staff see their own ("My Requests").',
        <>Open a request to see where the asset moves from and to. Approve or reject it there <AdminOnly />; approving one that changes the end user asks for the new PAR No.</>,
      ]} />
      <p className="mt-3">The same page also has <strong>Update Status</strong> for a quick condition or status change.</p>
    </>,
  },
  {
    id: 'maintenance',
    title: 'Maintenance',
    body: <Bullets items={[
      'Each record has a type (Preventive, Corrective or Repair), a status (Scheduled, Ongoing or Completed), findings, the work done, and parts and labor lines that add up to the cost.',
      <>To mark a repair <strong>Completed</strong>, add at least one <strong>before</strong> photo and one <strong>after</strong> photo (Photos).</>,
      'Print maintenance card prints the asset\'s Repair and Maintenance Card.',
      'Staff requests show "Awaiting approval"; use the filter to see only those. Staff can edit a record once it is approved.',
      <>Approve, reject and delete records <AdminOnly />.</>,
    ]} />,
  },
  {
    id: 'disposal',
    title: 'Disposal',
    body: <Bullets items={[
      'Only Repairable or Unserviceable assets can be disposed of.',
      'A disposal record gives the reason and the recommended method: Sale, Transfer, Destruction or Others.',
      'Its status goes Pending, then Approved, then Completed.',
      <>A disposed asset stays in the inventory with the status <strong>Disposed</strong>, for the audit trail. Once its disposal is Completed it no longer counts as on hand, and it appears as "Disposed" on its Property Card.</>,
      'The IIRUP report lists unserviceable property for inspection.',
    ]} />,
  },
  {
    id: 'history',
    title: 'Asset History',
    body: <Bullets items={[
      'History lists what happened to the assets: registered, transferred, maintenance and disposal, with who did it and when. Filter by event, person and date.',
      'Requests lists maintenance, disposal and transfer requests in one place with their status. Administrators can approve or reject them here too.',
    ]} />,
  },
  {
    id: 'reports',
    title: 'Reports',
    body: <>
      <p className="mb-2">Each report can be printed or downloaded as Excel. Staff reports cover their own offices.</p>
      <Terms rows={[
        ['RPCPPE', 'Report on the Physical Count of Property, Plant and Equipment, one form per category. The as-at date and the accountable officer can be edited on the page.'],
        ['Condition Report', 'Assets grouped by condition.'],
        ['Replacement Forecast', 'Assets reaching the end of their useful life, by year, with the estimated cost to replace.'],
        ['Depreciation Schedule', 'Monthly depreciation, accumulated depreciation and book value, following the Accounting Office\'s schedule (5% residual value).'],
        ['Repair and Maintenance Card', 'The maintenance card of the assets you pick.'],
        ['PAR', 'Property Acknowledgment Receipts.'],
        ['Property Card', 'The history of a transferred asset: receipts, transfers and disposal.'],
        ['IIRUP', 'Inventory and Inspection Report of Unserviceable Property.'],
      ]} />
    </>,
  },
  {
    id: 'notifications',
    title: 'Notifications',
    body: <p>The bell at the top right gathers what needs you: reminders, approvals waiting (administrators), your pending and rejected requests, account matters and asset issues. A red count shows how many are new; filter by kind at the top of the panel, and click one to go to the records it is about. Changes other people make also appear live without refreshing the page.</p>,
  },
  {
    id: 'admin',
    title: 'Administration',
    admin: true,
    body: <Terms rows={[
      ['Offices', 'The offices of the municipal hall and their property codes (the last part of the property number).'],
      ['Categories', 'Categories, their property codes, useful life in years (used for replacement and depreciation) and their list of articles. The renumber panel re-makes property numbers once codes are set.'],
      ['Personnel', 'Everyone with an account. Assign each person\'s office here; staff only see that office\'s assets.'],
      ['Accounts', 'Create accounts and set roles. Accounts are deactivated, never deleted; an account that holds assets must hand them to another account first.'],
      ['Audit Logs', 'Every action in the system with who and when. Entries older than a year move to the archive, which can be exported as CSV.'],
      ['Recovery', 'Deleted assets and records. Restore them, or delete them for good.'],
    ]} />,
  },
  {
    id: 'mobile',
    title: 'Mobile app',
    body: <Bullets items={[
      <>An Android app is available from <strong>Docs &gt; Mobile App</strong> in the menu. It installs over older versions and asks you to update when a new one is out.</>,
      'It covers the same work: assets, scanning QR stickers, transfers, maintenance with photos, disposal, reports and approvals.',
      'It works offline: the asset list stays readable, and changes and photos wait in "Waiting to Upload" until the phone is back online. If someone changed the same record meanwhile, the app asks which version to keep.',
    ]} />,
  },
]

function UserGuide() {
  const isAdmin = useSelector((s) => s.auth.user?.role === 'ADMIN')

  return (
    <MainLayout>
      <div className="max-w-5xl mx-auto">
        <header className="mb-6">
          <p className="text-sm text-slate-600 dark:text-zinc-400 max-w-2xl">
            How to use the San Jose GSO Enterprise Asset Management System. Parts marked <AdminOnly /> are done by an administrator{isAdmin ? '.' : '; ask one when you need them.'}
          </p>
        </header>

        <div className="lg:grid lg:grid-cols-[13rem_1fr] lg:gap-8 items-start">
          <nav aria-label="Contents" className="mb-6 lg:mb-0 lg:sticky lg:top-0">
            <p className="text-2xs font-semibold uppercase tracking-widest text-slate-500 dark:text-zinc-500 mb-2">Contents</p>
            <ol className="flex flex-wrap gap-1.5 lg:flex-col lg:gap-0.5">
              {SECTIONS.map((s, i) => (
                <li key={s.id}>
                  <a href={`#${s.id}`}
                    onClick={(e) => { e.preventDefault(); document.getElementById(s.id)?.scrollIntoView({ behavior: 'smooth', block: 'start' }) }}
                    className="inline-block lg:block px-2.5 py-1 lg:py-1.5 rounded-md text-sm text-slate-700 dark:text-zinc-300 bg-slate-100 lg:bg-transparent dark:bg-zinc-800 lg:dark:bg-transparent hover:bg-slate-100 dark:hover:bg-zinc-800 hover:text-slate-900 dark:hover:text-white transition-colors">
                    <span className="text-slate-400 dark:text-zinc-500 tabular-nums mr-1.5">{i + 1}.</span>{s.title}
                  </a>
                </li>
              ))}
            </ol>
          </nav>

          <div className="space-y-4 min-w-0">
            {SECTIONS.map((s, i) => (
              <section key={s.id} id={s.id} aria-labelledby={`${s.id}-title`} className={`${CARD} p-5 sm:p-6 scroll-mt-4`}>
                <h2 id={`${s.id}-title`} className="text-base font-semibold text-slate-900 dark:text-white mb-3">
                  <span className="text-slate-400 dark:text-zinc-500 tabular-nums mr-2">{i + 1}.</span>{s.title}
                  {s.admin && <AdminOnly />}
                </h2>
                <div className="text-sm leading-relaxed text-slate-700 dark:text-zinc-300">{s.body}</div>
              </section>
            ))}
          </div>
        </div>
      </div>
    </MainLayout>
  )
}

export default UserGuide
