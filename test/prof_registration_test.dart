import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xofer/core/theme/app_theme.dart';
import 'package:xofer/features/profile/data/cpf.dart';
import 'package:xofer/l10n/app_localizations.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/partner_role.dart';
import 'package:xofer/prof/domain/provider_account.dart';
import 'package:xofer/prof/presentation/registration_screen.dart';

class _Capture implements DocumentCapture {
  @override
  Future<CapturedDocument?> pick(DocumentSource source) async {
    return CapturedDocument(name: 'foto-$source.jpg', bytes: const [1, 2, 3]);
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pt'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

void main() {
  testWidgets('o motorista envia CNH, antecedentes e selfie para análise', (
    tester,
  ) async {
    ProviderApplication? saved;
    await tester.pumpWidget(
      _wrap(
        RegistrationScreen(
          role: PartnerRole.driver,
          phone: '+5511988887777',
          documentCapture: _Capture(),
          onSubmit: (application) async {
            saved = application;
            return ProviderAccount(
              id: 'user-1',
              role: application.role,
              fullName: application.fullName,
              document: application.document,
              phone: application.phone,
              email: application.email,
              status: ProviderStatus.analise,
            );
          },
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('registration_name')),
      'Adelcio Rodrigues',
    );
    await tester.enterText(
      find.byKey(const Key('registration_document')),
      '39053344705',
    );
    await tester.enterText(
      find.byKey(const Key('registration_email')),
      'adelcio@xofer.app',
    );
    await tester.tap(find.byKey(const Key('registration_continue')));
    await tester.pump();

    expect(find.byKey(const Key('document_crlv')), findsNothing);
    await tester.tap(find.byKey(const Key('document_cnh')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('document_criminal')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('registration_continue')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('document_selfie')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('registration_continue')));
    await tester.pump();
    await tester.pump();

    expect(saved?.role, PartnerRole.driver);
    expect(saved?.fullName, 'Adelcio Rodrigues');
    expect(saved?.document, Cpf.digitsOnly('39053344705'));
    expect(saved?.crlv, isNull);
    expect(find.text('Cadastro em análise'), findsNothing);
  });

  testWidgets('o motoboy precisa do CRLV da moto', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RegistrationScreen(
          role: PartnerRole.courier,
          phone: '+5511988887777',
          documentCapture: _Capture(),
          onSubmit: (application) async => ProviderAccount(
            id: 'user-1',
            role: application.role,
            fullName: application.fullName,
            document: application.document,
            phone: application.phone,
            email: application.email,
            status: ProviderStatus.analise,
          ),
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('registration_name')),
      'Ana Costa',
    );
    await tester.enterText(
      find.byKey(const Key('registration_document')),
      '39053344705',
    );
    await tester.enterText(
      find.byKey(const Key('registration_email')),
      'ana@xofer.app',
    );
    await tester.tap(find.byKey(const Key('registration_continue')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('document_cnh')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('document_criminal')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('registration_continue')));
    await tester.pump();

    expect(find.text('Anexe todos os documentos pedidos.'), findsOneWidget);
    expect(find.byKey(const Key('document_crlv')), findsOneWidget);
  });
}
