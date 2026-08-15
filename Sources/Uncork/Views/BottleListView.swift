import SwiftUI

/// 主界面：瓶卡片网格 + 新建/重命名/删除
struct BottleListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreate = false
    @State private var bottleToRename: Bottle?
    @State private var bottleToDelete: Bottle?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if appState.store.bottles.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 230), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(appState.store.bottles) { bottle in
                                BottleCardView(bottle: bottle)
                                    .onTapGesture(count: 2) {
                                        appState.selectedBottleID = bottle.id
                                    }
                                    .contextMenu {
                                        Button("打开") { appState.selectedBottleID = bottle.id }
                                        Button("重命名…") {
                                            renameText = bottle.name
                                            bottleToRename = bottle
                                        }
                                        Divider()
                                        Button("删除…", role: .destructive) {
                                            bottleToDelete = bottle
                                        }
                                    }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("开瓶器")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("新建瓶", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(item: $appState.selectedBottleID) { id in
                if let bottle = appState.store.bottle(withID: id) {
                    BottleDetailView(bottle: bottle)
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateBottleView()
            }
            .alert("重命名瓶", isPresented: renameBinding) {
                TextField("名称", text: $renameText)
                Button("确定") {
                    if let bottle = bottleToRename {
                        try? appState.store.rename(bottle, to: renameText)
                    }
                    bottleToRename = nil
                }
                Button("取消", role: .cancel) { bottleToRename = nil }
            }
            .alert("删除瓶？", isPresented: deleteBinding) {
                Button("删除", role: .destructive) {
                    if let bottle = bottleToDelete {
                        Task {
                            try? await appState.store.delete(bottle, wine: appState.wine)
                        }
                    }
                    bottleToDelete = nil
                }
                Button("取消", role: .cancel) { bottleToDelete = nil }
            } message: {
                Text("将删除瓶「\(bottleToDelete?.name ?? "")」及其中的所有 Windows 程序和文件，此操作不可恢复。")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wineglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("还没有瓶")
                .font(.title3)
            Text("瓶是独立的 Windows 环境，点击右上角「新建瓶」开始。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { bottleToRename != nil },
            set: { if !$0 { bottleToRename = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { bottleToDelete != nil },
            set: { if !$0 { bottleToDelete = nil } }
        )
    }
}
