import 'package:flutter/material.dart';
import '../../auth/model/user_model.dart' show roleLabel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/account_model.dart';
import '../provider/account_provider.dart';
import '../../../shared/widgets/ui.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/provider/auth_provider.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/paginated_list_view.dart';
import '../../../core/platform.dart';

class AccountListScreen extends ConsumerStatefulWidget {
  const AccountListScreen({super.key});

  @override
  ConsumerState<AccountListScreen> createState() => _AccountListScreenState();
}

class _AccountListScreenState extends ConsumerState<AccountListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(accountSearchProvider);
    final state = ref.watch(accountsPagedProvider(search));
    final isAdmin = ref.watch(authProvider).value?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(accountsPagedProvider(search)),
            ),
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: const Text('New Account'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: () async {
                  final result = await context.push<bool>('/accounts/new');
                  if (result == true) ref.invalidate(accountsPagedProvider(search));
                },
              ),
            ),
        ],
        bottom: ListToolbar(
          controller: _searchCtrl,
          hintText: 'Search username or full name',
          onSearch: (v) => ref.read(accountSearchProvider.notifier).state = v,
        ),
      ),
      body: PaginatedListView<AccountModel>(
        state: state,
        emptyMessage: 'No accounts found.',
        onLoadMore: () => ref.read(accountsPagedProvider(search).notifier).loadMore(),
        onRefresh: () => ref.read(accountsPagedProvider(search).notifier).refresh(),
        itemBuilder: (context, account, i) => _AccountCard(
          account: account,
          onTap: () async {
            final result = await context.push<bool>('/accounts/${account.id}/edit', extra: account);
            if (result == true) ref.invalidate(accountsPagedProvider(search));
          },
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final AccountModel account;
  final VoidCallback onTap;

  const _AccountCard({required this.account, required this.onTap});

  Color get _roleColor => account.role == 'ADMIN' ? AppTheme.brand : AppTheme.info;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = account.fullName.trim().isEmpty ? '?' : account.fullName.trim()[0].toUpperCase();
    return RecordCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // initial in a plain circle, like the web avatar
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.subtle, shape: BoxShape.circle, border: Border.all(color: c.border)),
            child: Text(initial, style: TextStyle(color: c.heading, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardTitle(account.fullName, maxLines: 1),
                const SizedBox(height: 2),
                CodeText('@${account.username}', size: 14),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  StatusBadge(label: roleLabel(account.role), color: _roleColor),
                  if (!account.isActive) const StatusBadge(label: 'Inactive', color: AppTheme.statusDisposed),
                ]),
                if (account.officeName != null) ...[
                  const SizedBox(height: 8),
                  MetaLine(Icons.apartment_rounded, account.officeName!),
                ],
                const SizedBox(height: 4),
                account.email != null
                    ? MetaLine(Icons.mail_rounded, account.email!)
                    : Text('No email on file — forgot-password won\'t work',
                        style: TextStyle(
                            color: context.isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24), fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
