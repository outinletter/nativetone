import UIKit

/// Shows the Korean text being typed inside the keyboard (SmartBoard-style compose bar).
final class BufferBarView: UIView {
    var onClear: (() -> Void)?

    private let label = UILabel()
    private let clearButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardTheme.bar.withAlphaComponent(1)

        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingHead
        label.font = .systemFont(ofSize: 18)
        label.translatesAutoresizingMaskIntoConstraints = false

        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = .tertiaryLabel
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addAction(UIAction { [weak self] _ in self?.onClear?() }, for: .touchUpInside)

        addSubview(label)
        addSubview(clearButton)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 36),
            clearButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        setText("")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setText(_ text: String) {
        if text.isEmpty {
            label.text = ""
            label.textColor = .tertiaryLabel
            clearButton.isHidden = true
        } else {
            label.text = text + "▏"
            label.textColor = .label
            clearButton.isHidden = false
        }
    }
}
