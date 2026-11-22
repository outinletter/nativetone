import UIKit

/// Strip above the keys: [✨] [suggestion / status] [tone].
final class SuggestionBarView: UIView {
    enum State {
        case idle
        case loading
        case result(String)
        case ok(String)
        case message(String)
    }

    /// When on, the idle hint says suggestions appear by themselves.
    var autoMode = true
    var onTrigger: (() -> Void)?
    var onApply: (() -> Void)?
    var onToneTap: (() -> Void)?
    var onStateChange: (() -> Void)?

    private(set) var state: State = .idle

    private let sparkleButton = UIButton(type: .system)
    private let suggestionButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let toneButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardTheme.bar

        sparkleButton.setTitle("✨", for: .normal)
        sparkleButton.titleLabel?.font = .systemFont(ofSize: 22)
        sparkleButton.addAction(UIAction { [weak self] _ in self?.onTrigger?() }, for: .touchUpInside)

        suggestionButton.contentHorizontalAlignment = .leading
        suggestionButton.titleLabel?.numberOfLines = 2
        suggestionButton.titleLabel?.lineBreakMode = .byTruncatingTail
        suggestionButton.titleLabel?.font = .systemFont(ofSize: 14)
        suggestionButton.addAction(UIAction { [weak self] _ in self?.suggestionTapped() }, for: .touchUpInside)

        toneButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        toneButton.addAction(UIAction { [weak self] _ in self?.onToneTap?() }, for: .touchUpInside)

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [sparkleButton, spinner, suggestionButton, toneButton])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            sparkleButton.widthAnchor.constraint(equalToConstant: 40),
            spinner.widthAnchor.constraint(equalToConstant: 24),
            toneButton.widthAnchor.constraint(equalToConstant: 76),
        ])
        toneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        set(.idle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setTone(_ tone: Tone) {
        toneButton.setTitle("\(tone.emoji) \(tone.label)", for: .normal)
    }

    func set(_ newState: State) {
        state = newState
        defer { onStateChange?() }
        switch newState {
        case .idle:
            spinner.stopAnimating()
            suggestionButton.setTitle(autoMode ? "입력하면 자연스러운 문장이 여기에 떠요" : "문장 교정하기", for: .normal)
            suggestionButton.setTitleColor(.secondaryLabel, for: .normal)
        case .loading:
            spinner.startAnimating()
            suggestionButton.setTitle("교정 중…", for: .normal)
            suggestionButton.setTitleColor(.secondaryLabel, for: .normal)
        case .result(let text):
            spinner.stopAnimating()
            suggestionButton.setTitle(text, for: .normal)
            suggestionButton.setTitleColor(.label, for: .normal)
        case .ok(let text):
            spinner.stopAnimating()
            suggestionButton.setTitle(text, for: .normal)
            suggestionButton.setTitleColor(.systemGreen, for: .normal)
        case .message(let text):
            spinner.stopAnimating()
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
