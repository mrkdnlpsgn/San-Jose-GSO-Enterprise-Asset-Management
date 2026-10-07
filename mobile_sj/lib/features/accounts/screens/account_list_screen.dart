import 'package:flutter/material.dart';
import '../../auth/model/user_model.dart' show roleLabel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../model/account_model.dart';
import '../provider/account_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/provider/auth_provider.dart';
import '../../../shared/widgets/app_search_field.dart';
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
        title: const Text('Manage Accounts'),
        actions: [
          if (isDesktopPlatform)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(accountsPagedProvider(search)),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search by username, full name...',
              onChanged: (v) => ref.read(accountSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              backgroundColor: AppTheme.brand,
              child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
              onPressed: () async {
                final result = await context.push<bool>('/accounts/new');
                if (result == true) ref.invalidate(accountsPagedProvider(search));
              },
            )
          : null,
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

  Color get _roleColor => account.role == 'ADMIN' ? AppTheme.brand : AppTheme.statusAssigned;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _roleColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  account.role == 'ADMIN' ? Icons.admin_panel_settings_outlined : Icons.person_outline_rounded,
                  color: _roleColor, size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(account.fullName,
                              style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (!account.isActive)
                          const StatusBadge(label: 'Inactive', color: AppTheme.statusDisposed, dense: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('@${account.username} · ${roleLabel(account.role)}',
                        style: TextStyle(color: _roleColor, fontSize: 12)),
                    if (account.officeName != null) ...[
                      const SizedBox(height: 2),
                      Text(account.officeName!,
                          style: TextStyle(color: context.colors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      account.email ?? 'No email on file (forgot-password unavailable)',
                      style: TextStyle(
                        color: account.email != null ? context.colors.textTertiary : Colors.amber,
                        fontSize: 11.5,
                        fontStyle: account.email != null ? FontStyle.normal : FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
