import Domain

public extension QuotaMonitor {
    convenience init(
        providers: [AIProvider],
        alerter: (any QuotaAlerter)? = nil,
        powerStateProvider: (any PowerStateProvider)? = SystemPowerStateProvider()
    ) {
        self.init(
            providers: providers,
            alerter: alerter,
            clock: SystemClock(),
            powerStateProvider: powerStateProvider
        )
    }
}
