import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://rtcyetcyhdrajvcstvlj.supabase.co")!,
    supabaseKey: "sb_publishable_qokFAlPkk0H9eCbbPbEm9w_zY1gns0c",
    options: .init(
        auth: .init(
            emitLocalSessionAsInitialSession: true
        )
    )
)
