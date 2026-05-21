import SwiftUI

// MARK: - Sender Icon Spec

/// A bundled brand icon spec for a known email sender domain.
///
/// Rendering priority inside SenderAvatarView:
/// 1. If `slug` is non-nil and the matching `sender-icon-{slug}` asset exists,
///    render the bundled SVG (template-tinted with `foreground`) on a circle
///    filled with `background`.
/// 2. Otherwise, render `letter` on a circle filled with `background`.
///
/// Either path is **instant, offline, and crisp** at any size — no network.
struct MacSenderIconSpec {
    let letter: String
    let background: Color
    let foreground: Color
    /// simple-icons slug. When set, SenderAvatarView renders
    /// `Image("sender-icon-\(slug)")` instead of the letter.
    let slug: String?

    init(_ letter: String, _ background: Color, foreground: Color = .white, slug: String? = nil) {
        self.letter = letter
        self.background = background
        self.foreground = foreground
        self.slug = slug
    }
}

// MARK: - Sender Icon Registry

/// Maps known brand root domains to bundled icon specs.
///
/// Lookup extracts the root domain from the sender's email address
/// (e.g. `auth.github.com` → `github.com`), then returns a spec if
/// the domain is a recognised brand. Personal email provider domains
/// (gmail.com, icloud.com, etc.) always return nil so personal senders
/// fall through to initials.
enum MacSenderIconRegistry {

    static func icon(for email: String) -> MacSenderIconSpec? {
        guard let domain = rootDomain(from: email),
              !personalProviders.contains(domain) else { return nil }
        return icons[domain]
    }

    // MARK: - Private helpers

    private static func rootDomain(from email: String) -> String? {
        let lower = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIdx = lower.lastIndex(of: "@"),
              atIdx < lower.index(before: lower.endIndex) else { return nil }
        let domain = String(lower[lower.index(after: atIdx)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        if parts.count >= 3 {
            let tld2 = parts.suffix(2).joined(separator: ".")
            let multiTLDs: Set<String> = [
                "co.uk", "org.uk", "gov.uk", "ac.uk",
                "com.au", "co.jp", "com.br", "co.in",
            ]
            if multiTLDs.contains(tld2) { return parts.suffix(3).joined(separator: ".") }
        }
        return parts.suffix(2).joined(separator: ".")
    }

    private static let personalProviders: Set<String> = [
        "gmail.com", "googlemail.com",
        "outlook.com", "hotmail.com", "live.com", "msn.com",
        "yahoo.com", "yahoo.co.uk", "yahoo.fr", "yahoo.de", "yahoo.co.jp", "yahoo.com.br",
        "icloud.com", "me.com", "mac.com",
        "protonmail.com", "proton.me", "protonmail.ch",
        "zohomail.com", "zoho.com",
        "yandex.com", "yandex.ru",
        "mail.ru", "bk.ru", "inbox.ru", "list.ru",
        "gmx.com", "gmx.net", "gmx.de", "gmx.at",
        "aol.com", "aol.co.uk",
        "fastmail.com", "fastmail.fm",
        "hey.com",
        "tutanota.com", "tutamail.com",
    ]

    // MARK: - Icon table
    //
    // SVG assets live in Assets.xcassets/SenderIcons/sender-icon-{slug}.imageset
    // and are sourced from the simple-icons project (CC0 public domain).
    // To add a new brand, run the sync script and add an entry below with its
    // slug.

    // swiftlint:disable closure_body_length
    private static let icons: [String: MacSenderIconSpec] = {
        var d: [String: MacSenderIconSpec] = [:]

        // Google ecosystem
        let googleBlue = Color(red: 0.259, green: 0.522, blue: 0.957)
        let googleSlug = "google"
        d["google.com"]    = .init("G", googleBlue, slug: googleSlug)
        d["google.co.uk"]  = .init("G", googleBlue, slug: googleSlug)
        d["google.de"]     = .init("G", googleBlue, slug: googleSlug)
        d["google.fr"]     = .init("G", googleBlue, slug: googleSlug)
        d["google.ca"]     = .init("G", googleBlue, slug: googleSlug)
        d["google.com.au"] = .init("G", googleBlue, slug: googleSlug)
        d["google.co.jp"]  = .init("G", googleBlue, slug: googleSlug)

        // GitHub
        let ghDark = Color(red: 0.141, green: 0.161, blue: 0.180)
        d["github.com"] = .init("GH", ghDark, slug: "github")
        d["github.io"]  = .init("GH", ghDark, slug: "github")

        // Apple
        d["apple.com"] = .init("A", Color(red: 0.33, green: 0.33, blue: 0.35), slug: "apple")

        // Microsoft
        let msBlue = Color(red: 0.0, green: 0.643, blue: 0.937)
        d["microsoft.com"] = .init("M", msBlue, slug: "microsoft")
        d["office.com"]    = .init("O", Color(red: 0.847, green: 0.231, blue: 0.004))
        d["azure.com"]     = .init("Az", Color(red: 0.0, green: 0.467, blue: 0.824))

        // Amazon / AWS
        let amznYellow = Color(red: 1.0, green: 0.600, blue: 0.0)
        let amznDark   = Color(red: 0.137, green: 0.184, blue: 0.243)
        d["amazon.com"]    = .init("A", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazon.co.uk"]  = .init("A", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazon.de"]     = .init("A", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazon.fr"]     = .init("A", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazon.es"]     = .init("A", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazon.it"]     = .init("A", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazon.se"]     = .init("A", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazon.nl"]     = .init("A", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazonaws.com"] = .init("AWS", amznYellow, foreground: amznDark, slug: "amazon")
        d["amazonses.com"] = .init("A", amznYellow, foreground: amznDark, slug: "amazon")

        // AI
        d["anthropic.com"]  = .init("A", Color(red: 0.812, green: 0.475, blue: 0.290), slug: "anthropic")
        d["openai.com"]     = .init("AI", Color(red: 0.05, green: 0.05, blue: 0.05), slug: "openai")
        d["mistral.ai"]     = .init("M", Color(red: 1.0, green: 0.561, blue: 0.0), slug: "mistralai")
        d["perplexity.ai"]  = .init("P", Color(red: 0.098, green: 0.690, blue: 0.667), slug: "perplexity")

        // Productivity / SaaS
        d["notion.so"]     = .init("N", Color(red: 0.05, green: 0.05, blue: 0.05), slug: "notion")
        d["slack.com"]     = .init("#", Color(red: 0.290, green: 0.082, blue: 0.294), slug: "slack")
        d["figma.com"]     = .init("F", Color(red: 0.949, green: 0.306, blue: 0.118), slug: "figma")
        d["linear.app"]    = .init("L", Color(red: 0.369, green: 0.416, blue: 0.824), slug: "linear")
        d["airtable.com"]  = .init("A", Color(red: 0.988, green: 0.706, blue: 0.0), foreground: .black, slug: "airtable")
        d["monday.com"]    = .init("M", Color(red: 0.965, green: 0.169, blue: 0.329))
        d["asana.com"]     = .init("A", Color(red: 0.976, green: 0.420, blue: 0.408), slug: "asana")
        d["typeform.com"]  = .init("T", Color(red: 0.149, green: 0.149, blue: 0.157), slug: "typeform")
        d["canva.com"]     = .init("C", Color(red: 0.0, green: 0.769, blue: 0.800), slug: "canva")
        d["webflow.com"]   = .init("WF", Color(red: 0.263, green: 0.325, blue: 1.0), slug: "webflow")

        // Project management / issue tracking
        d["atlassian.com"]  = .init("A", Color(red: 0.0, green: 0.322, blue: 0.800), slug: "atlassian")
        d["jira.com"]       = .init("J", Color(red: 0.0, green: 0.322, blue: 0.800), slug: "atlassian")

        // Social / Communication
        let xBlack = Color(red: 0.05, green: 0.05, blue: 0.05)
        d["linkedin.com"]  = .init("in", Color(red: 0.039, green: 0.400, blue: 0.757), slug: "linkedin")
        d["twitter.com"]   = .init("𝕏",  xBlack, slug: "x")
        d["x.com"]         = .init("𝕏",  xBlack, slug: "x")
        let fbBlue = Color(red: 0.094, green: 0.467, blue: 0.949)
        d["facebook.com"]      = .init("f", fbBlue, slug: "facebook")
        // Facebook's transactional / notification mail domains route through these.
        // Map them so notification senders (`messages@priority.facebookmail.com`,
        // `noreply@facebookmail.com`, etc.) get the Facebook logo instead of a
        // gray "JV"-style initial.
        d["facebookmail.com"]  = .init("f", fbBlue, slug: "facebook")
        d["facebookmail.net"]  = .init("f", fbBlue, slug: "facebook")
        d["fb.com"]            = .init("f", fbBlue, slug: "facebook")
        d["fbcdn.net"]         = .init("f", fbBlue, slug: "facebook")
        d["instagram.com"] = .init("IG", Color(red: 0.882, green: 0.192, blue: 0.424), slug: "instagram")
        d["meta.com"]      = .init("M",  Color(red: 0.024, green: 0.408, blue: 0.882), slug: "meta")
        d["discord.com"]   = .init("D",  Color(red: 0.345, green: 0.396, blue: 0.949), slug: "discord")
        d["telegram.org"]  = .init("T",  Color(red: 0.165, green: 0.671, blue: 0.937), slug: "telegram")
        d["whatsapp.com"]  = .init("W",  Color(red: 0.145, green: 0.831, blue: 0.400), slug: "whatsapp")
        d["reddit.com"]    = .init("R",  Color(red: 1.0, green: 0.267, blue: 0.063), slug: "reddit")
        d["tiktok.com"]    = .init("T",  Color(red: 0.05, green: 0.05, blue: 0.05), slug: "tiktok")

        // Newsletter platforms
        d["substack.com"]    = .init("S", Color(red: 1.0, green: 0.404, blue: 0.098), slug: "substack")
        d["beehiiv.com"]     = .init("B", Color(red: 1.0, green: 0.380, blue: 0.329))
        d["convertkit.com"]  = .init("CK", Color(red: 0.933, green: 0.278, blue: 0.100), slug: "kit")
        d["kit.com"]         = .init("K", Color(red: 0.933, green: 0.278, blue: 0.100), slug: "kit")
        d["mailerlite.com"]  = .init("ML", Color(red: 0.020, green: 0.659, blue: 0.576))

        // Entertainment / Media
        d["netflix.com"] = .init("N", Color(red: 0.898, green: 0.035, blue: 0.078), slug: "netflix")
        d["spotify.com"] = .init("S", Color(red: 0.114, green: 0.722, blue: 0.329), slug: "spotify")
        d["youtube.com"] = .init("▶", Color(red: 1.0, green: 0.0, blue: 0.0), slug: "youtube")
        d["twitch.tv"]   = .init("T", Color(red: 0.573, green: 0.267, blue: 0.996), slug: "twitch")
        d["hbo.com"]     = .init("H", Color(red: 0.412, green: 0.133, blue: 0.745), slug: "hbo")
        d["disneyplus.com"] = .init("D+", Color(red: 0.067, green: 0.110, blue: 0.400))

        // Commerce / Payments
        d["stripe.com"]            = .init("S",  Color(red: 0.388, green: 0.357, blue: 1.0), slug: "stripe")
        let paypalBlue = Color(red: 0.0, green: 0.188, blue: 0.529)
        d["paypal.com"]            = .init("P", paypalBlue, slug: "paypal")
        d["paypal.co.uk"]          = .init("P", paypalBlue, slug: "paypal")
        d["paypal.de"]             = .init("P", paypalBlue, slug: "paypal")
        d["paypal.fr"]             = .init("P", paypalBlue, slug: "paypal")
        d["paypal.it"]             = .init("P", paypalBlue, slug: "paypal")
        d["paypal.es"]             = .init("P", paypalBlue, slug: "paypal")
        d["paypal.se"]             = .init("P", paypalBlue, slug: "paypal")
        d["paypal.nl"]             = .init("P", paypalBlue, slug: "paypal")
        d["paypal.com.au"]         = .init("P", paypalBlue, slug: "paypal")
        d["shopify.com"]           = .init("S",  Color(red: 0.588, green: 0.749, blue: 0.278), slug: "shopify")
        d["squarespace.com"]       = .init("S",  Color(red: 0.133, green: 0.133, blue: 0.133), slug: "squarespace")
        d["wix.com"]               = .init("W",  Color(red: 0.0, green: 0.400, blue: 1.0), slug: "wix")
        d["klarna.com"]            = .init("K",  Color(red: 1.0, green: 0.706, blue: 0.788), foreground: .black, slug: "klarna")
        d["braintreepayments.com"] = .init("BT", Color(red: 0.235, green: 0.584, blue: 0.808))

        // Developer / Infrastructure
        d["vercel.com"]       = .init("▲", Color(red: 0.05, green: 0.05, blue: 0.05), slug: "vercel")
        d["cloudflare.com"]   = .init("CF", Color(red: 0.965, green: 0.510, blue: 0.122), slug: "cloudflare")
        d["resend.com"]       = .init("R",  Color(red: 0.05, green: 0.05, blue: 0.05), slug: "resend")
        d["netlify.com"]      = .init("N",  Color(red: 0.0, green: 0.780, blue: 0.718), slug: "netlify")
        d["heroku.com"]       = .init("H",  Color(red: 0.431, green: 0.239, blue: 0.647), slug: "heroku")
        d["digitalocean.com"] = .init("DO", Color(red: 0.0, green: 0.451, blue: 1.0), slug: "digitalocean")
        d["supabase.com"]     = .init("S",  Color(red: 0.235, green: 0.808, blue: 0.557), slug: "supabase")
        d["railway.app"]      = .init("R",  Color(red: 0.498, green: 0.267, blue: 0.871), slug: "railway")
        d["render.com"]       = .init("R",  Color(red: 0.263, green: 0.259, blue: 0.259), slug: "render")
        d["sendgrid.net"]     = .init("SG", Color(red: 0.102, green: 0.510, blue: 0.886), slug: "sendgrid")
        d["mailgun.com"]      = .init("MG", Color(red: 0.941, green: 0.420, blue: 0.400), slug: "mailgun")
        d["twilio.com"]       = .init("T",  Color(red: 0.949, green: 0.169, blue: 0.275), slug: "twilio")
        d["postmark.com"]     = .init("P",  Color(red: 1.0, green: 0.447, blue: 0.051))
        d["sentry.io"]        = .init("S",  Color(red: 0.361, green: 0.255, blue: 0.576), slug: "sentry")

        // CRM / Marketing / Support
        d["hubspot.com"]    = .init("H",  Color(red: 1.0, green: 0.478, blue: 0.349), slug: "hubspot")
        d["salesforce.com"] = .init("SF", Color(red: 0.0, green: 0.631, blue: 0.878), slug: "salesforce")
        d["zendesk.com"]    = .init("Z",  Color(red: 0.012, green: 0.212, blue: 0.239), slug: "zendesk")
        d["intercom.com"]   = .init("I",  Color(red: 0.157, green: 0.431, blue: 0.980), slug: "intercom")
        d["mailchimp.com"]  = .init("MC", Color(red: 0.016, green: 0.016, blue: 0.016), slug: "mailchimp")

        // Cloud Storage
        d["dropbox.com"] = .init("D", Color(red: 0.0, green: 0.380, blue: 1.0), slug: "dropbox")
        d["box.com"]     = .init("B", Color(red: 0.0, green: 0.490, blue: 1.0), slug: "box")

        // Design / Creative
        d["adobe.com"] = .init("Ae", Color(red: 0.937, green: 0.024, blue: 0.024), slug: "adobe")

        return d
    }()
    // swiftlint:enable closure_body_length
}
