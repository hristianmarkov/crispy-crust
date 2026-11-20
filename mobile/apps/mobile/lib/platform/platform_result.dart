enum CapabilityStatus { available, permissionRequired, denied, unsupported, unconfigured, failed }

class CapabilityResult<T> {
  const CapabilityResult(this.status, this.message, [this.value]);
  const CapabilityResult.available(T value, [String message = 'Available'])
      : this(CapabilityStatus.available, message, value);
  final CapabilityStatus status;
  final String message;
  final T? value;
  bool get isAvailable => status == CapabilityStatus.available;
}
