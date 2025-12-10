/// Configuration for Nirvana V2 protocol
class NirvanaConfig {
  final String programId;
  final String tenantAccount;
  final String priceCurve;

  // Token mints
  final String anaMint;
  final String nirvMint;
  final String pranaMint;
  final String usdcMint;
  final String mettaMint;

  // Vault accounts
  final String tenantUsdcVault;
  final String tenantAnaVault;
  final String escrowRevNirv;
  final String escrowNirvAccount;

  const NirvanaConfig({
    required this.programId,
    required this.tenantAccount,
    required this.priceCurve,
    required this.anaMint,
    required this.nirvMint,
    required this.pranaMint,
    required this.usdcMint,
    required this.mettaMint,
    required this.tenantUsdcVault,
    required this.tenantAnaVault,
    required this.escrowRevNirv,
    required this.escrowNirvAccount,
  });

  factory NirvanaConfig.mainnet() {
    return const NirvanaConfig(
      programId: 'NirvHuZvrm2zSxjkBvSbaF2tHfP5j7cvMj9QmdoHVwb',
      tenantAccount: 'BcAoCEdkzV2J21gAjCCEokBw5iMnAe96SbYo9F6QmKWV',
      priceCurve: 'Fx5u5BCTwpckbB6jBbs13nDsRabHb5bq2t2hBDszhSbd',
      // Official Nirvana token addresses - DO NOT CHANGE
      anaMint: '5DkzT65YJvCsZcot9L6qwkJnsBCPmKHjJz3QU7t7QeRW',
      nirvMint: '3eamaYJ7yicyRd3mYz4YeNyNPGVo6zMmKUp5UP25AxRM',
      pranaMint: 'CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N',
      usdcMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
      mettaMint: 'Aeg9L4a2dRX2PfUvcWeTAyYBfa7vAYXczfDrx1MSiTYS',
      tenantUsdcVault: 'FhTJEGXVwj4M6NQ1tPu9jgDZUXWQ9w2hP89ebZHwrJPS',
      tenantAnaVault: 'EkwPHXXZNAguNoxeftVRXThCQJfD6EaG852pDsYLs2eB',
      escrowRevNirv: '42rJYSmYHqbn5mk992xAoKZnWEiuMzr6u6ydj9m8fAjP',
      escrowNirvAccount: 'v2EeX2VjgsMbwokj6UDmAm691oePzrcvKpK5DT7LwbQ',
    );
  }
}