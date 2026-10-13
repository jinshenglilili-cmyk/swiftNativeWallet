//
//  XMarkButton.swift
//  SwiftfulCrypto
//
//  Created by LW on 5/9/21.
//

import SwiftUI

struct XMarkButton: View {

    // 可选外部关闭动作：放在 .toolbar 里时，子视图自身的 @Environment(\.dismiss)
    // 可能与 sheet 呈现上下文断连导致点 × 无效，此时应由父视图传入关闭回调
    var action: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: {
            if let action {
                action()
            } else {
                dismiss()
            }
        }, label: {
            Image(systemName: "xmark")
                .font(.headline)
                .padding()
                .contentShape(Rectangle())
        })
    }
}

struct XMarkButton_Previews: PreviewProvider {
    static var previews: some View {
        XMarkButton()
    }
}
