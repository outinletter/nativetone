import UIKit

/// Minimal strip above the keys: [suggestion / status] [tone]. Tap the text to rewrite or apply.
final class SuggestionBarView: UIView {
    enum State {
        case idle
        case loading
        case result(String)
        case ok(String)
        case message(String)
    }

    var autoMode = true
    var onTrigger: (() -> Void)?
    var onApply: (() -> Void)?
    var onToneTap: (() -> Void)?
    var onStateChange: (() -> Void)?

    private(set) var state: State = .idle
    private var tone: Tone = AppSettings.tone

    private let suggestionButton = UIButton(type: .system)
    private let toneButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardTheme.bar

        suggestionButton.contentHorizontalAlignment = .leading
        suggestionButton.titleLabel?.numberOfLines = 2
        suggestionButton.titleLabel?.lineBreakMode = .byTruncatingTail
        suggestionButton.titleLabel?.font = .systemFont(ofSize: 15)
        suggestionButton.addAction(UIAction { [weak self] _ in self?.suggestionTapped() }, for: .touchUpInside)

        toneButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        toneButton.addAction(UIAction { [weak self] _ in self?.onToneTap?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [suggestionButton, toneButton])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            toneButton.widthAnchor.constraint(equalToConstant: 64),
        ])
        toneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        set(.idle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setTone(_ tone: Tone) {
        self.tone = tone
        toneButton.setTitle(tone.label, for: .normal)
        if case .idle = state { set(.idle) }
    }

    /// Text being composed (Korean / Japanese / Chinese). Shown inside the bar, no extra row.
    var composing = "" {
        didSet { render() }
    }

    private var statusText = ""
    private var statusColor: UIColor = .secondaryLabel
    private var statusIsHint = false

    func set(_ newState: State) {
        state = newState
        defer { onStateChange?() }
        switch newState {
        case .idle:
            statusText = L("입력하면 \(tone.adjective) 원어민 표현으로 바꿔요", "Type to get a \(tone.adjective) native-speaker version")
            statusColor = .tertiaryLabel
            statusIsHint = true
        case .loading:
            statusText = "…"; statusColor = .secondaryLabel; statusIsHint = false
        case .result(let text):
            statusText = text; statusColor = .label; statusIsHint = false
        case .ok(let text):
            statusText = text; statusColor = .secondaryLabel; statusIsHint = false
        case .message(let text):
            statusText = text; statusColor = .systemRed; statusIsHint = false
        }
        render()
    }

    private func render() {
        let out = NSMutableAttributedString()
        func add(_ text: String, size: CGFloat, color: UIColor) {
            out.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: color]))
        }
        if composing.isEmpty {
            add(statusText, size: 15, color: statusColor)
        } else if statusIsHint {
            add(composing, size: 18, color: .label)
        } else {
            add(composing, size: 12, color: .secondaryLabel)
            add("\n", size: 12, color: .secondaryLabel)
            add(statusText, size: 15, color: statusColor)
        }
        suggestionButton.setAttributedTitle(out, for: .normal)
    }

    private func suggestionTapped() {
        switch state {
        case .result: onApply?()
        case .idle, .message: onTrigger?()
        case .loading, .ok: break
        }
    }
}
