import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In pt, this message translates to:
  /// **'Xofer'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In pt, this message translates to:
  /// **'Entrar'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Informe o número do Celular para receber um código de verificação.'**
  String get loginSubtitle;

  /// No description provided for @phoneLabel.
  ///
  /// In pt, this message translates to:
  /// **'Número do Celular'**
  String get phoneLabel;

  /// No description provided for @phoneHint.
  ///
  /// In pt, this message translates to:
  /// **'912 345 678'**
  String get phoneHint;

  /// No description provided for @sendOtp.
  ///
  /// In pt, this message translates to:
  /// **'Enviar código'**
  String get sendOtp;

  /// No description provided for @otpSentTo.
  ///
  /// In pt, this message translates to:
  /// **'Código enviado para {phone}'**
  String otpSentTo(String phone);

  /// No description provided for @otpLabel.
  ///
  /// In pt, this message translates to:
  /// **'Código OTP'**
  String get otpLabel;

  /// No description provided for @otpHint.
  ///
  /// In pt, this message translates to:
  /// **'000000'**
  String get otpHint;

  /// No description provided for @verifyOtp.
  ///
  /// In pt, this message translates to:
  /// **'Verificar e entrar'**
  String get verifyOtp;

  /// No description provided for @changeNumber.
  ///
  /// In pt, this message translates to:
  /// **'Alterar número'**
  String get changeNumber;

  /// No description provided for @resendOtp.
  ///
  /// In pt, this message translates to:
  /// **'Reenviar código'**
  String get resendOtp;

  /// No description provided for @invalidPhone.
  ///
  /// In pt, this message translates to:
  /// **'Informe um número de Celular válido.'**
  String get invalidPhone;

  /// No description provided for @invalidOtp.
  ///
  /// In pt, this message translates to:
  /// **'Informe o código de 6 dígitos.'**
  String get invalidOtp;

  /// No description provided for @homeWelcome.
  ///
  /// In pt, this message translates to:
  /// **'Para onde vamos?'**
  String get homeWelcome;

  /// No description provided for @signOut.
  ///
  /// In pt, this message translates to:
  /// **'Terminar sessão'**
  String get signOut;

  /// No description provided for @genericError.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível concluir o pedido. Tente novamente.'**
  String get genericError;

  /// No description provided for @completeProfileTitle.
  ///
  /// In pt, this message translates to:
  /// **'Complete o cadastro'**
  String get completeProfileTitle;

  /// No description provided for @completeProfileSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Informe seu nome e documento para continuar.'**
  String get completeProfileSubtitle;

  /// No description provided for @fullNameLabel.
  ///
  /// In pt, this message translates to:
  /// **'Nome completo'**
  String get fullNameLabel;

  /// No description provided for @fullNameHint.
  ///
  /// In pt, this message translates to:
  /// **'Como no documento'**
  String get fullNameHint;

  /// No description provided for @documentLabel.
  ///
  /// In pt, this message translates to:
  /// **'CPF'**
  String get documentLabel;

  /// No description provided for @documentHint.
  ///
  /// In pt, this message translates to:
  /// **'000.000.000-00'**
  String get documentHint;

  /// No description provided for @saveProfile.
  ///
  /// In pt, this message translates to:
  /// **'Salvar e continuar'**
  String get saveProfile;

  /// No description provided for @invalidFullName.
  ///
  /// In pt, this message translates to:
  /// **'Informe o nome completo.'**
  String get invalidFullName;

  /// No description provided for @invalidDocument.
  ///
  /// In pt, this message translates to:
  /// **'Informe um CPF válido.'**
  String get invalidDocument;

  /// No description provided for @checkingProfile.
  ///
  /// In pt, this message translates to:
  /// **'A verificar o cadastro...'**
  String get checkingProfile;

  /// No description provided for @retry.
  ///
  /// In pt, this message translates to:
  /// **'Tentar novamente'**
  String get retry;

  /// No description provided for @myLocation.
  ///
  /// In pt, this message translates to:
  /// **'Minha localização'**
  String get myLocation;

  /// No description provided for @locationServiceDisabled.
  ///
  /// In pt, this message translates to:
  /// **'O GPS está desativado. Ative a localização do aparelho para vermos onde você está.'**
  String get locationServiceDisabled;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In pt, this message translates to:
  /// **'Sem a permissão de localização não conseguimos centralizar o mapa. Permita o acesso e tente de novo.'**
  String get locationPermissionDenied;

  /// No description provided for @locationPermissionDeniedForever.
  ///
  /// In pt, this message translates to:
  /// **'A localização está bloqueada para o Xofer. Ative a permissão nas configurações do aparelho.'**
  String get locationPermissionDeniedForever;

  /// No description provided for @locationUnavailable.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível obter a sua posição. Tente novamente.'**
  String get locationUnavailable;

  /// No description provided for @openLocationSettings.
  ///
  /// In pt, this message translates to:
  /// **'Ativar GPS'**
  String get openLocationSettings;

  /// No description provided for @openAppSettings.
  ///
  /// In pt, this message translates to:
  /// **'Abrir configurações'**
  String get openAppSettings;

  /// No description provided for @noAddressResults.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum endereço encontrado.'**
  String get noAddressResults;

  /// No description provided for @addressSearchError.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível buscar endereços. Tente novamente.'**
  String get addressSearchError;

  /// No description provided for @clearSearch.
  ///
  /// In pt, this message translates to:
  /// **'Limpar busca'**
  String get clearSearch;

  /// No description provided for @originLabel.
  ///
  /// In pt, this message translates to:
  /// **'Origem'**
  String get originLabel;

  /// No description provided for @destinationLabel.
  ///
  /// In pt, this message translates to:
  /// **'Destino'**
  String get destinationLabel;

  /// No description provided for @locatingOrigin.
  ///
  /// In pt, this message translates to:
  /// **'Obtendo seu endereço...'**
  String get locatingOrigin;

  /// No description provided for @originUnavailable.
  ///
  /// In pt, this message translates to:
  /// **'Localização atual'**
  String get originUnavailable;

  /// No description provided for @rideSummaryTitle.
  ///
  /// In pt, this message translates to:
  /// **'Resumo da corrida'**
  String get rideSummaryTitle;

  /// No description provided for @estimatedPrice.
  ///
  /// In pt, this message translates to:
  /// **'Preço estimado'**
  String get estimatedPrice;

  /// No description provided for @paymentMethod.
  ///
  /// In pt, this message translates to:
  /// **'Pagamento'**
  String get paymentMethod;

  /// No description provided for @creditCard.
  ///
  /// In pt, this message translates to:
  /// **'Cartão de Crédito'**
  String get creditCard;

  /// No description provided for @savedCard.
  ///
  /// In pt, this message translates to:
  /// **'Visa •••• 4242'**
  String get savedCard;

  /// No description provided for @pix.
  ///
  /// In pt, this message translates to:
  /// **'PIX'**
  String get pix;

  /// No description provided for @pixCopyPaste.
  ///
  /// In pt, this message translates to:
  /// **'Copia e cola'**
  String get pixCopyPaste;

  /// No description provided for @copyPixCode.
  ///
  /// In pt, this message translates to:
  /// **'Copiar código'**
  String get copyPixCode;

  /// No description provided for @pixCopied.
  ///
  /// In pt, this message translates to:
  /// **'Código copiado'**
  String get pixCopied;

  /// No description provided for @confirmDriver.
  ///
  /// In pt, this message translates to:
  /// **'Confirmar Motorista + Resgate'**
  String get confirmDriver;

  /// No description provided for @activeTripTitle.
  ///
  /// In pt, this message translates to:
  /// **'Rastreamento ativo'**
  String get activeTripTitle;

  /// No description provided for @driverOnTheWay.
  ///
  /// In pt, this message translates to:
  /// **'Motorista a caminho do resgate'**
  String get driverOnTheWay;

  /// No description provided for @headingToDestination.
  ///
  /// In pt, this message translates to:
  /// **'A caminho do destino'**
  String get headingToDestination;

  /// No description provided for @tripArrived.
  ///
  /// In pt, this message translates to:
  /// **'Você chegou ao destino'**
  String get tripArrived;

  /// No description provided for @followRoute.
  ///
  /// In pt, this message translates to:
  /// **'Acompanhar trajeto'**
  String get followRoute;

  /// No description provided for @assignedDriver.
  ///
  /// In pt, this message translates to:
  /// **'Ana Costa'**
  String get assignedDriver;

  /// No description provided for @assignedVehicle.
  ///
  /// In pt, this message translates to:
  /// **'Honda Civic · ABC-1D23'**
  String get assignedVehicle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
