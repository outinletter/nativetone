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
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            toneButton.widthAnchor.constraint(equalToConstant: 64),
        ])
        toneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        set(.idle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setTone(_ tone: Tone) {
        toneButton.setTitle(tone.label, for: .normal)
    }

    func set(_ newState: State) {
        state = newState
        defer { onStateChange?() }
        switch newState {
        case .idle:
            suggestionButton.setTitle(L("입력하면 교정 문장이 표시돼요", "Your rewrite appears here"), for: .normal)
            suggestionButton.setTitleColor(.tertiaryLabel, for: .normal)
        case .loading:
            suggestionButton.setTitle("…", for: .normal)
            suggestionButton.setTitleColor(.secondaryLabel, for: .normal)
        case .result(let text):
            suggestionButton.setTitle(text, for: .normal)
            suggestionButton.setTitleColor(.label, for: .normal)
        case .ok(let text):
            suggestionButton.setTitle(text, for: .normal)
            suggestionButton.setTitleColor(.secondaryLabel, for: .normal)
        case .message(let text):
            suggestionButton.setTitle(text, for: .normal)
            suggestionButton.setTitleColor(.systemRed, for: .normal)
        }
    }

    private func suggestionTapped() {
        switch state {
        case .result: onApply?()
        case .idle, .message: onTrigger?()
        case .loading, .ok: break
        }
    }
}
