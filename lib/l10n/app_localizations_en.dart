// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Xofer';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginSubtitle =>
      'Enter your mobile number to receive a verification code.';

  @override
  String get phoneLabel => 'Mobile number';

  @override
  String get phoneHint => '912 345 678';

  @override
  String get sendOtp => 'Send code';

  @override
  String otpSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get otpLabel => 'OTP code';

  @override
  String get otpHint => '000000';

  @override
  String get verifyOtp => 'Verify and sign in';

  @override
  String get changeNumber => 'Change number';

  @override
  String get resendOtp => 'Resend code';

  @override
  String get invalidPhone => 'Enter a valid mobile number.';

  @override
  String get invalidOtp => 'Enter the 6-digit code.';

  @override
  String get homeWelcome => 'Where to?';

  @override
  String get signOut => 'Sign out';

  @override
  String get genericError =>
      'The request could not be completed. Please try again.';

  @override
  String get completeProfileTitle => 'Complete your profile';

  @override
  String get completeProfileSubtitle => 'Enter your name and ID to continue.';

  @override
  String get fullNameLabel => 'Full name';

  @override
  String get fullNameHint => 'As on your ID';

  @override
  String get documentLabel => 'CPF';

  @override
  String get documentHint => '000.000.000-00';

  @override
  String get saveProfile => 'Save and continue';

  @override
  String get invalidFullName => 'Enter your full name.';

  @override
  String get invalidDocument => 'Enter a valid CPF.';

  @override
  String get checkingProfile => 'Checking your profile...';

  @override
  String get retry => 'Try again';

  @override
  String get myLocation => 'My location';

  @override
  String get locationServiceDisabled =>
      'GPS is turned off. Enable location on your device so we can see where you are.';

  @override
  String get locationPermissionDenied =>
      'We need location permission to center the map. Allow access and try again.';

  @override
  String get locationPermissionDeniedForever =>
      'Location is blocked for Xofer. Enable the permission in your device settings.';

  @override
  String get locationUnavailable =>
      'We couldn\'t get your position. Please try again.';

  @override
  String get openLocationSettings => 'Turn on GPS';

  @override
  String get openAppSettings => 'Open settings';

  @override
  String get noAddressResults => 'No addresses found.';

  @override
  String get addressSearchError => 'Address search failed. Please try again.';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get originLabel => 'Origin';

  @override
  String get destinationLabel => 'Destination';

  @override
  String get locatingOrigin => 'Finding your address...';

  @override
  String get originUnavailable => 'Current location';

  @override
  String get rideSummaryTitle => 'Ride summary';

  @override
  String get estimatedPrice => 'Estimated price';

  @override
  String get paymentMethod => 'Payment';

  @override
  String get creditCard => 'Credit card';

  @override
  String get savedCard => 'Visa •••• 4242';

  @override
  String get pix => 'PIX';

  @override
  String get pixCopyPaste => 'Copy and paste';

  @override
  String get copyPixCode => 'Copy code';

  @override
  String get pixCopied => 'Code copied';

  @override
  String get confirmDriver => 'Confirm driver + pickup';

  @override
  String get activeTripTitle => 'Active tracking';

  @override
  String get driverOnTheWay => 'Driver on the way to pickup';

  @override
  String get headingToDestination => 'Heading to destination';

  @override
  String get tripArrived => 'You arrived at the destination';

  @override
  String get followRoute => 'Follow route';

  @override
  String get assignedDriver => 'Ana Costa';

  @override
  String get assignedVehicle => 'Honda Civic · ABC-1D23';
}
