//
//  LegacyImagePicker.swift
//  bbb
//
//  透明 Host 在模板页内 `present` 系统相册；仅用 `UIImagePickerController`（照片库导航栏左侧系统「取消」）。
//  `PHPickerViewController` 在部分系统/机型上顶部无明确取消入口，故不采用。
//  生成页本身已是全屏叠层：相册再用 `pageSheet` 二次弹出时，部分系统上导航栏「取消」会缺失；故统一用 `fullScreen`。
//  部分 iOS 版本在第二次 `present` 相册时根页仍可能不出现系统「取消」，故在根控制器上按需补一个 `UIBarButtonItem`（与系统行为一致：取消即 dismiss）。
//

import SwiftUI
import UIKit

struct LegacyImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> PhotoPickerHostViewController {
        let vc = PhotoPickerHostViewController()
        context.coordinator.host = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: PhotoPickerHostViewController, context: Context) {
        context.coordinator.parent = self
        uiViewController.sync(isPresented: isPresented, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: LegacyImagePicker!
        weak var host: PhotoPickerHostViewController?

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let img = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.host?.clearMidPresentationFlag()
                    self.parent.image = img
                    self.parent.isPresented = false
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.host?.clearMidPresentationFlag()
                    self.parent.isPresented = false
                }
            }
        }

        /// `UIImagePickerController` 同时需要 `UINavigationControllerDelegate`，以便在相册导航栈回到根页时补全缺失的「取消」。
        func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
            guard navigationController is UIImagePickerController else { return }
            patchRootCancelIfNeeded(on: navigationController, visible: viewController)
        }

        /// 与系统「取消」等效：结束选图并同步 SwiftUI `isPresented`。
        @objc func legacyPickerCancelTapped() {
            guard let picker = host?.presentedViewController as? UIImagePickerController else { return }
            imagePickerControllerDidCancel(picker)
        }

        /// 仅在相册根页且左侧无任何按钮时补「取消」，避免覆盖相册内层级的返回按钮。
        fileprivate func patchRootCancelIfNeeded(on navigationController: UINavigationController, visible: UIViewController) {
            guard navigationController.viewControllers.first === visible else { return }
            guard visible.navigationItem.leftBarButtonItem == nil else { return }
            let items = visible.navigationItem.leftBarButtonItems
            if let items, !items.isEmpty { return }
            visible.navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(legacyPickerCancelTapped)
            )
        }
    }
}

// MARK: - Host

final class PhotoPickerHostViewController: UIViewController {
    private var isMidPresentation = false

    func clearMidPresentationFlag() {
        isMidPresentation = false
    }

    func sync(isPresented: Bool, coordinator: LegacyImagePicker.Coordinator) {
        coordinator.host = self
        if !isPresented {
            if presentedViewController != nil {
                presentedViewController?.dismiss(animated: true) { [weak self] in
                    self?.isMidPresentation = false
                }
            } else {
                isMidPresentation = false
            }
            return
        }
        if let presented = presentedViewController {
            // 相册已展示且 Binding 仍为 true：正常状态，勿 dismiss 再 present（会与用户点「取消」时的系统 dismiss 竞态，出现闪开再关）。
            if presented is UIImagePickerController {
                return
            }
            presented.dismiss(animated: false) { [weak self] in
                guard let self = self else { return }
                self.isMidPresentation = false
                DispatchQueue.main.async {
                    self.sync(isPresented: true, coordinator: coordinator)
                }
            }
            return
        }
        guard !isMidPresentation else { return }
        guard viewIfLoaded?.window != nil else {
            DispatchQueue.main.async { [weak self] in
                self?.sync(isPresented: isPresented, coordinator: coordinator)
            }
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            isMidPresentation = false
            coordinator.parent.isPresented = false
            return
        }

        isMidPresentation = true
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        picker.navigationBar.isHidden = false
        present(picker, animated: true) { [weak self, weak coordinator] in
            self?.isMidPresentation = false
            guard let coordinator else { return }
            // 根栈构建略晚于 `present` 完成，延迟一帧再补一次，覆盖「第二次打开无取消」的系统表现。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if let nav = coordinator.host?.presentedViewController as? UINavigationController,
                   let top = nav.topViewController ?? nav.viewControllers.first {
                    coordinator.patchRootCancelIfNeeded(on: nav, visible: top)
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }
}
