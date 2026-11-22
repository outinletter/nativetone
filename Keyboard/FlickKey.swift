import UIKit

/// iPhone-style kana flick key: tap for the main character, or press and flick
/// left / up / right / down to pick another one from the popup cross.
final class FlickKey: UIView {
    /// Order: center, left, up, right, down (empty string = unused direction).
    private let chars: [String]
    var onCommit: ((String) -> Void)?

    private let label = UILabel()
    private var popup: UIView?
    private var cells: [UILabel] = []
    private var raised: [(UIView, CGFloat)] = []
    private var selected = 0
    private var start = CGPoint.zero

    init(chars: [String]) {
        self.chars = chars
        super.init(frame: .zero)
        backgroundColor = KeyboardTheme.letterKey
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.3

        label.text = chars.first
        label.font = .systemFont(ofSize: 22)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        start = t.location(in: self)
        selected = 0
        if AppSettings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        showPopup()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let dx = p.x - start.x, dy = p.y - start.y
        var idx = 0
        if hypot(dx, dy) > 18 {
            if abs(dx) > abs(dy) { idx = dx < 0 ? 1 : 3 } else { idx = dy < 0 ? 2 : 4 }
        }
        if idx != 0, idx >= chars.count || chars[idx].isEmpty { idx = 0 }
        if idx != selected {
            selected = idx
            highlight()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let out = chars[selected]
        hidePopup()
        if !out.isEmpty { onCommit?(out) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        hidePopup()
    }

    // MARK: - Popup cross

    private func showPopup() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let container = UIView(frame: CGRect(x: -w, y: -h, width: w * 3, height: h * 3))
        container.isUserInteractionEnabled = false
        let spots = [CGPoint(x: w, y: h), CGPoint(x: 0, y: h), CGPoint(x: w, y: 0), CGPoint(x: 2 * w, y: h), CGPoint(x: w, y: 2 * h)]
        cells = []
        for (i, c) in chars.enumerated() where i < spots.count {
            let l = UILabel(frame: CGRect(origin: spots[i], size: CGSize(width: w, height: h)))
            l.text = c
            l.font = .systemFont(ofSize: 24)
            l.textAlignment = .center
            l.layer.cornerRadius = 8
            l.layer.masksToBounds = true
            l.isHidden = c.isEmpty
            container.addSubview(l)
            cells.append(l)
        }
        addSubview(container)
        popup = container
        raiseAncestors()
        highlight()
    }

    private func highlight() {
        for (i, l) in cells.enumerated() {
            let on = i == selected
            l.backgroundColor = on ? .systemBlue : KeyboardTheme.specialKey
            l.textColor = on ? .white : .label
        }
    }

    private func hidePopup() {
        popup?.removeFromSuperview()
        popup = nil
        cells = []
        for (v, z) in raised { v.layer.zPosition = z }
        raised = []
    }

    /// Sibling stacks draw in order, so lift every ancestor above its neighbours while the popup is open.
    private func raiseAncestors() {
        var v: UIView? = self
        while let x = v, x.superview != nil {
            raised.append((x, x.layer.zPosition))
            x.layer.zPosition = 20
            v = x.superview
        }
    }
}
