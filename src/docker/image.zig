pub const Annotation = @import("image/attestations.zig").Annotation;
pub const Attestation = @import("image/attestations.zig").Attestation;
pub const AttestationList = @import("image/attestations.zig").AttestationList;
pub const AttestationsOptions = @import("image/attestations.zig").AttestationsOptions;
pub const Descriptor = @import("image/attestations.zig").Descriptor;
pub const Platform = @import("image/attestations.zig").Platform;
pub const attestations = @import("image/attestations.zig").attestations;

pub const BuildOptions = @import("image/build.zig").BuildOptions;
pub const build = @import("image/build.zig").build;

pub const BuildPrune = @import("image/prune.zig").BuildPrune;
pub const BuildPruneOptions = @import("image/prune.zig").BuildPruneOptions;
pub const buildPrune = @import("image/prune.zig").buildPrune;

pub const Commit = @import("image/commit.zig").Commit;
pub const CommitOptions = @import("image/commit.zig").CommitOptions;
pub const commit = @import("image/commit.zig").commit;

pub const CreateOptions = @import("image/transfer.zig").CreateOptions;
pub const create = @import("image/transfer.zig").create;

pub const Delete = @import("image/delete.zig").Delete;
pub const DeleteList = @import("image/delete.zig").DeleteList;
pub const RemoveOptions = @import("image/delete.zig").RemoveOptions;
pub const remove = @import("image/delete.zig").remove;

pub const ExportImageOptions = @import("image/transfer.zig").ExportImageOptions;
pub const ExportImagesOptions = @import("image/transfer.zig").ExportImagesOptions;
pub const exportImage = @import("image/transfer.zig").exportImage;
pub const exportImages = @import("image/transfer.zig").exportImages;

pub const History = @import("image/history.zig").History;
pub const HistoryList = @import("image/history.zig").HistoryList;
pub const HistoryOptions = @import("image/history.zig").HistoryOptions;
pub const history = @import("image/history.zig").history;

pub const ImagePrune = @import("image/prune.zig").ImagePrune;
pub const PruneOptions = @import("image/prune.zig").PruneOptions;
pub const prune = @import("image/prune.zig").prune;

pub const Inspect = @import("image/inspect.zig").Inspect;
pub const InspectOptions = @import("image/inspect.zig").InspectOptions;
pub const inspect = @import("image/inspect.zig").inspect;

pub const LoadOptions = @import("image/transfer.zig").LoadOptions;
pub const load = @import("image/transfer.zig").load;

pub const Search = @import("image/search.zig").Search;
pub const SearchList = @import("image/search.zig").SearchList;
pub const SearchOptions = @import("image/search.zig").SearchOptions;
pub const search = @import("image/search.zig").search;

pub const ExportStream = @import("image/transfer.zig").ExportStream;
pub const ProgressStream = @import("image/transfer.zig").ProgressStream;

pub const Summary = @import("image/list.zig").Summary;
pub const SummaryList = @import("image/list.zig").SummaryList;
pub const ListOptions = @import("image/list.zig").ListOptions;
pub const list = @import("image/list.zig").list;

pub const TagOptions = @import("image/tag.zig").TagOptions;
pub const tag = @import("image/tag.zig").tag;

pub const PushOptions = @import("image/transfer.zig").PushOptions;

test {
    _ = @import("image/attestations.zig");
    _ = @import("image/build.zig");
    _ = @import("image/commit.zig");
    _ = @import("image/delete.zig");
    _ = @import("image/history.zig");
    _ = @import("image/inspect.zig");
    _ = @import("image/list.zig");
    _ = @import("image/prune.zig");
    _ = @import("image/search.zig");
    _ = @import("image/strings.zig");
    _ = @import("image/tag.zig");
    _ = @import("image/transfer.zig");
}
