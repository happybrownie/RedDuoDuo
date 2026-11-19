import SwiftUI
import UIKit
import Combine

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var mobile = ""
    @State private var code = ""
    @State private var csrfToken = ""
    @State private var countdown = 0
    @State private var sendingCode = false
    @State private var loggingIn = false
    @State private var statusMessage: String?
    @State private var isError = false

    @State private var mfaContext: MfaContext?
    @State private var pollingMfa = false
    @State private var mfaPollTask: Task<Void, Never>?
    @State private var mfaPollHint = "请先按上方步骤发送短信，然后点击「已发送，继续验证」"
    @State private var copiedHint: String?

    private var accent: Color { RD.Palette.accent }
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                RD.Palette.background.ignoresSafeArea()
                RadialGradient(
                    colors: [RD.Palette.gemDeep.opacity(0.28), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 340
                )
                .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard
                        if let mfa = mfaContext {
                            mfaGuidanceCard(mfa)
                        } else {
                            formCard
                        }
                        if let statusMessage {
                            statusBanner(statusMessage, isError: isError)
                        }
                        securityFootnote
                    }
                    .padding(18)
                }
            }
            .navigationTitle(mfaContext == nil ? "登录红果账号" : "短信安全验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(RD.Palette.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        mfaPollTask?.cancel()
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            .onReceive(timer) { _ in
                if countdown > 0 { countdown -= 1 }
            }
            .onDisappear {
                mfaPollTask?.cancel()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: RD.Space.sm) {
            HStack(spacing: 10) {
                RDGemPlayMark(size: 30)
                Text("红果漫剧")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
            }
            Text("红果账号短信登录")
                .font(RD.Font.display)
                .foregroundStyle(.white)
            Text("账号凭据仅保存在本机，绑定当前设备身份")
                .font(RD.Font.body)
                .foregroundStyle(RD.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, RD.Space.md)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("手机号（中国大陆 +86）")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 10) {
                Text("+86")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RD.Palette.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                TextField("请输入 11 位手机号", text: $mobile)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("login-mobile-field")
            }
            .padding(12)
            .background(RD.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous))

            Text("短信验证码")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 10) {
                TextField("请输入验证码", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("login-code-field")

                Button {
                    Task { await sendCode() }
                } label: {
                    if sendingCode {
                        ProgressView().controlSize(.small).tint(.white)
                            .frame(minWidth: 88)
                    } else {
                        Text(countdown > 0 ? "\(countdown)s 后重发" : "获取验证码")
                            .font(.caption.bold())
                            .frame(minWidth: 88)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background {
                    if canSendCode {
                        RDGemFacetSurface(shape: Capsule(), shadowRadius: 6)
                    } else {
                        Capsule()
                            .fill(RD.Palette.surfaceRaised)
                            .overlay(Capsule().strokeBorder(RD.Palette.hairline, lineWidth: 0.7))
                    }
                }
                .foregroundStyle(canSendCode ? .white : RD.Palette.textSecondary)
                .disabled(!canSendCode)
                .accessibilityIdentifier("login-send-code-button")
            }
            .padding(12)
            .background(RD.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous))

            Button {
                Task { await submitLogin() }
            } label: {
                HStack {
                    Spacer()
                    if loggingIn {
                        ProgressView().tint(.white)
                    } else {
                        Text("登录")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background {
                    let shape = RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
                    if canLogin {
                        RDGemFacetSurface(shape: shape, shadowRadius: 8)
                    } else {
                        shape
                            .fill(RD.Palette.surfaceRaised)
                            .overlay(shape.strokeBorder(RD.Palette.hairline, lineWidth: 0.7))
                    }
                }
                .foregroundStyle(canLogin ? .white : RD.Palette.textSecondary)
            }
            .disabled(!canLogin)
            .padding(.top, 6)
            .accessibilityIdentifier("login-submit-button")
        }
        .padding(RD.Space.lg)
        .rdCard()
    }

    private func mfaGuidanceCard(_ mfa: MfaContext) -> some View {
        let targetNumber = mfa.channelMobile.isEmpty ? "10691859839103" : mfa.channelMobile
        let smsBody = mfa.smsContent.isEmpty ? "YZ" : mfa.smsContent

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(RD.Palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("需要发送上行短信完成验证")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("新设备登录保护（错误码 2046）")
                        .font(.caption)
                        .foregroundStyle(RD.Palette.warning)
                }
            }

            Text("由于当前使用新设备登录，请使用本机号码发送一条普通验证短信以确认本人操作：")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))

            VStack(alignment: .leading, spacing: 12) {
                stepRow(num: "1", text: "使用本机号码（\(ManjuAPI.normalizeMobile(mobile))）打开手机「信息」App")
                stepRow(num: "2", text: "将下方指定短信内容发送到接收号码（运营商按普通短信标准资费收取）")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("接收号码")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                            Text(targetNumber)
                                .font(.title3.monospacedDigit().bold())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Button("复制号码") {
                            UIPasteboard.general.string = targetNumber
                            RDHaptics.shared.playCopyStamp()
                            showCopied("已复制接收号码")
                        }
                        .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 10, verticalPadding: 6))
                    }

                    Divider().background(Color.white.opacity(0.12))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("发送内容")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                            Text(smsBody)
                                .font(.title3.monospaced().bold())
                                .foregroundStyle(RD.Palette.gemRim)
                        }
                        Spacer()
                        Button("复制内容") {
                            UIPasteboard.general.string = smsBody
                            RDHaptics.shared.playCopyStamp()
                            showCopied("已复制短信内容")
                        }
                        .buttonStyle(RDGemSecondaryButtonStyle(capsule: true, horizontalPadding: 10, verticalPadding: 6))
                    }

                    if let copiedHint {
                        Text(copiedHint)
                            .font(.caption2)
                            .foregroundStyle(RD.Palette.success)
                    }
                }
                .padding(14)
                .background(RD.Palette.background, in: RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
                        .strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.75)
                )

                stepRow(num: "3", text: "短信发送成功后返回本页，点击下方「已发送，继续验证」")
            }

            Button {
                RDHaptics.shared.playGlassTap()
                openMessagesApp(number: targetNumber, body: smsBody)
            } label: {
                Label("打开系统短信发送", systemImage: "message.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RD.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous)
                            .strokeBorder(RD.Gem.cardBorderGradient, lineWidth: 0.75)
                    )
                    .foregroundStyle(.white)
            }

            Button {
                startMfaVerificationPolling(mfa)
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    if pollingMfa {
                        ProgressView().tint(.white)
                        Text("正在核验上行短信…")
                    } else {
                        Text("已发送，继续验证")
                    }
                    Spacer()
                }
                .font(.headline)
                .padding(.vertical, 14)
                .background {
                    RDGemFacetSurface(
                        shape: RoundedRectangle(cornerRadius: RD.Radius.control, style: .continuous),
                        shadowRadius: 8
                    )
                }
                .foregroundStyle(.white)
            }
            .disabled(pollingMfa)
            .accessibilityIdentifier("mfa-confirm-sent-button")

            Text(mfaPollHint)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

            HStack {
                Button("返回重填验证码") {
                    mfaPollTask?.cancel()
                    pollingMfa = false
                    mfaContext = nil
                    statusMessage = nil
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if pollingMfa {
                    Button("停止轮询") {
                        mfaPollTask?.cancel()
                        pollingMfa = false
                        mfaPollHint = "已暂停核验，确认发出短信后可再次点击「已发送，继续验证」"
                    }
                    .font(.caption)
                    .foregroundStyle(RD.Palette.warning)
                }
            }
        }
        .padding(RD.Space.lg)
        .rdCard()
    }

    private func stepRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background {
                    RDGemFacetSurface(shape: Circle(), shadowRadius: 4, borderWidth: 0.8)
                }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusBanner(_ text: String, isError: Bool) -> some View {
        let tone = isError ? RD.Palette.warning : RD.Palette.success
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(tone)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .accessibilityIdentifier("login-status-text")
            Spacer()
        }
        .padding(14)
        .background(tone.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tone.opacity(0.35), lineWidth: 0.8))
    }

    private var securityFootnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.55))
            Text("• 游客状态下仍可正常浏览与播放；登录后可同步红果账号个性化推荐、云端观看记录与收藏。")
            Text("• 认证服务直连 security.snssdk.com，并使用本机固定设备身份完成签名。")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.45))
        .padding(.horizontal, 4)
    }

    private var canSendCode: Bool {
        !sendingCode && countdown == 0 && !ManjuAPI.normalizeMobile(mobile).isEmpty
    }

    private var canLogin: Bool {
        !loggingIn && !ManjuAPI.normalizeMobile(mobile).isEmpty && !code.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func showCopied(_ msg: String) {
        copiedHint = msg
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedHint == msg { copiedHint = nil }
        }
    }

    private func openMessagesApp(number: String, body: String) {
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "sms:\(number)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }

    private func sendCode() async {
        sendingCode = true
        statusMessage = nil
        isError = false
        do {
            let res = try await auth.sendCode(mobile: mobile)
            csrfToken = res.csrfToken
            countdown = res.retryTime
            statusMessage = "验证码已发送，请查收短信"
            isError = false
            RDHaptics.shared.playSmsSent()
        } catch {
            statusMessage = error.localizedDescription
            isError = true
            RDHaptics.shared.playMfaResult(success: false)
        }
        sendingCode = false
    }

    private func submitLogin() async {
        loggingIn = true
        statusMessage = nil
        isError = false
        do {
            let outcome = try await auth.smsLogin(mobile: mobile, code: code, csrfToken: csrfToken)
            switch outcome {
            case .success(let sess):
                statusMessage = "登录成功：\(sess.user.displayName)"
                isError = false
                RDHaptics.shared.playMfaResult(success: true)
                dismiss()
            case .mfa(let ctx):
                mfaContext = ctx
                mfaPollHint = "发送短信后，点击「已发送，继续验证」即可自动核验并完成登录"
                RDHaptics.shared.playMfaShieldAppear()
            }
        } catch {
            statusMessage = error.localizedDescription
            isError = true
            RDHaptics.shared.playMfaResult(success: false)
        }
        loggingIn = false
    }

    private func startMfaVerificationPolling(_ initialMfa: MfaContext) {
        mfaPollTask?.cancel()
        pollingMfa = true
        statusMessage = nil
        mfaPollHint = "正在向服务端查询上行短信状态…"

        mfaPollTask = Task { @MainActor in
            var currentMfa = initialMfa
            for attempt in 1...15 {
                if Task.isCancelled { return }
                do {
                    mfaPollHint = "正在核验上行短信（第 \(attempt)/15 次）…"
                    let state = try await auth.upsmsVerifyOnce(mfa: currentMfa)
                    switch state {
                    case .waiting:
                        mfaPollHint = "尚未收到运营商确认，3 秒后自动重试（第 \(attempt)/15 次）…"
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    case .registered(let newMfaToken):
                        currentMfa.mfaToken = newMfaToken
                        mfaContext = currentMfa
                        mfaPollHint = "上行短信已核验通过，正在完成登录…"
                        let sess = try await auth.completeMfaRelogin(
                            mobile: mobile,
                            code: code,
                            csrfToken: csrfToken,
                            mfa: currentMfa
                        )
                        pollingMfa = false
                        statusMessage = "登录成功：\(sess.user.displayName)"
                        isError = false
                        RDHaptics.shared.playMfaResult(success: true)
                        dismiss()
                        return
                    }
                } catch {
                    pollingMfa = false
                    statusMessage = error.localizedDescription
                    isError = true
                    mfaPollHint = "核验出错，请确认已发出短信后重试"
                    RDHaptics.shared.playMfaResult(success: false)
                    return
                }
            }
            pollingMfa = false
            mfaPollHint = "暂未收到运营商回执，请确认短信发送成功后再次点击「已发送，继续验证」"
            RDHaptics.shared.playMfaResult(success: false)
        }
    }
}
