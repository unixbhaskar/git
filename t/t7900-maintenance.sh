#!/bin/sh

test_description='git maintenance builtin'

. ./test-lib.sh

GIT_TEST_COMMIT_GRAPH=0
GIT_TEST_MULTI_PACK_INDEX=0

test_expect_success 'help text' '
	test_expect_code 129 git maintenance -h 2>err &&
	test_i18ngrep "usage: git maintenance run" err &&
	test_expect_code 128 git maintenance barf 2>err &&
	test_i18ngrep "invalid subcommand: barf" err &&
	test_expect_code 129 git maintenance 2>err &&
	test_i18ngrep "usage: git maintenance" err
'

test_expect_success 'run [--auto|--quiet]' '
	GIT_TRACE2_EVENT="$(pwd)/run-no-auto.txt" \
		git maintenance run 2>/dev/null &&
	GIT_TRACE2_EVENT="$(pwd)/run-auto.txt" \
		git maintenance run --auto 2>/dev/null &&
	GIT_TRACE2_EVENT="$(pwd)/run-no-quiet.txt" \
		git maintenance run --no-quiet 2>/dev/null &&
	test_subcommand git gc --quiet <run-no-auto.txt &&
	test_subcommand ! git gc --auto --quiet <run-auto.txt &&
	test_subcommand git gc --no-quiet <run-no-quiet.txt
'

test_expect_success 'maintenance.<task>.enabled' '
	git config maintenance.gc.enabled false &&
	git config maintenance.commit-graph.enabled true &&
	GIT_TRACE2_EVENT="$(pwd)/run-config.txt" git maintenance run 2>err &&
	test_subcommand ! git gc --quiet <run-config.txt &&
	test_subcommand git commit-graph write --split --reachable --no-progress <run-config.txt
'

test_expect_success 'run --task=<task>' '
	GIT_TRACE2_EVENT="$(pwd)/run-commit-graph.txt" \
		git maintenance run --task=commit-graph 2>/dev/null &&
	GIT_TRACE2_EVENT="$(pwd)/run-gc.txt" \
		git maintenance run --task=gc 2>/dev/null &&
	GIT_TRACE2_EVENT="$(pwd)/run-commit-graph.txt" \
		git maintenance run --task=commit-graph 2>/dev/null &&
	GIT_TRACE2_EVENT="$(pwd)/run-both.txt" \
		git maintenance run --task=commit-graph --task=gc 2>/dev/null &&
	test_subcommand ! git gc --quiet <run-commit-graph.txt &&
	test_subcommand git gc --quiet <run-gc.txt &&
	test_subcommand git gc --quiet <run-both.txt &&
	test_subcommand git commit-graph write --split --reachable --no-progress <run-commit-graph.txt &&
	test_subcommand ! git commit-graph write --split --reachable --no-progress <run-gc.txt &&
	test_subcommand git commit-graph write --split --reachable --no-progress <run-both.txt
'

test_expect_success 'core.commitGraph=false prevents write process' '
	GIT_TRACE2_EVENT="$(pwd)/no-commit-graph.txt" \
		git -c core.commitGraph=false maintenance run \
		--task=commit-graph 2>/dev/null &&
	test_subcommand ! git commit-graph write --split --reachable --no-progress \
		<no-commit-graph.txt
'

test_expect_success 'commit-graph auto condition' '
	COMMAND="maintenance run --task=commit-graph --auto --quiet" &&

	GIT_TRACE2_EVENT="$(pwd)/cg-no.txt" \
		git -c maintenance.commit-graph.auto=1 $COMMAND &&
	GIT_TRACE2_EVENT="$(pwd)/cg-negative-means-yes.txt" \
		git -c maintenance.commit-graph.auto="-1" $COMMAND &&

	test_commit first &&

	GIT_TRACE2_EVENT="$(pwd)/cg-zero-means-no.txt" \
		git -c maintenance.commit-graph.auto=0 $COMMAND &&
	GIT_TRACE2_EVENT="$(pwd)/cg-one-satisfied.txt" \
		git -c maintenance.commit-graph.auto=1 $COMMAND &&

	git commit --allow-empty -m "second" &&
	git commit --allow-empty -m "third" &&

	GIT_TRACE2_EVENT="$(pwd)/cg-two-satisfied.txt" \
		git -c maintenance.commit-graph.auto=2 $COMMAND &&

	COMMIT_GRAPH_WRITE="git commit-graph write --split --reachable --no-progress" &&
	test_subcommand ! $COMMIT_GRAPH_WRITE <cg-no.txt &&
	test_subcommand $COMMIT_GRAPH_WRITE <cg-negative-means-yes.txt &&
	test_subcommand ! $COMMIT_GRAPH_WRITE <cg-zero-means-no.txt &&
	test_subcommand $COMMIT_GRAPH_WRITE <cg-one-satisfied.txt &&
	test_subcommand $COMMIT_GRAPH_WRITE <cg-two-satisfied.txt
'

test_expect_success 'run --task=bogus' '
	test_must_fail git maintenance run --task=bogus 2>err &&
	test_i18ngrep "is not a valid task" err
'

test_expect_success 'run --task duplicate' '
	test_must_fail git maintenance run --task=gc --task=gc 2>err &&
	test_i18ngrep "cannot be selected multiple times" err
'

test_expect_success 'run --task=prefetch with no remotes' '
	git maintenance run --task=prefetch 2>err &&
	test_must_be_empty err
'

test_expect_success 'prefetch multiple remotes' '
	git clone . clone1 &&
	git clone . clone2 &&
	git remote add remote1 "file://$(pwd)/clone1" &&
	git remote add remote2 "file://$(pwd)/clone2" &&
	git -C clone1 switch -c one &&
	git -C clone2 switch -c two &&
	test_commit -C clone1 one &&
	test_commit -C clone2 two &&
	GIT_TRACE2_EVENT="$(pwd)/run-prefetch.txt" git maintenance run --task=prefetch 2>/dev/null &&
	fetchargs="--prune --no-tags --no-write-fetch-head --recurse-submodules=no --refmap= --quiet" &&
	test_subcommand git fetch remote1 $fetchargs +refs/heads/\\*:refs/prefetch/remote1/\\* <run-prefetch.txt &&
	test_subcommand git fetch remote2 $fetchargs +refs/heads/\\*:refs/prefetch/remote2/\\* <run-prefetch.txt &&
	test_path_is_missing .git/refs/remotes &&
	git log prefetch/remote1/one &&
	git log prefetch/remote2/two &&
	git fetch --all &&
	test_cmp_rev refs/remotes/remote1/one refs/prefetch/remote1/one &&
	test_cmp_rev refs/remotes/remote2/two refs/prefetch/remote2/two
'

test_expect_success 'loose-objects task' '
	# Repack everything so we know the state of the object dir
	git repack -adk &&

	# Hack to stop maintenance from running during "git commit"
	echo in use >.git/objects/maintenance.lock &&

	# Assuming that "git commit" creates at least one loose object
	test_commit create-loose-object &&
	rm .git/objects/maintenance.lock &&

	ls .git/objects >obj-dir-before &&
	test_file_not_empty obj-dir-before &&
	ls .git/objects/pack/*.pack >packs-before &&
	test_line_count = 1 packs-before &&

	# The first run creates a pack-file
	# but does not delete loose objects.
	git maintenance run --task=loose-objects &&
	ls .git/objects >obj-dir-between &&
	test_cmp obj-dir-before obj-dir-between &&
	ls .git/objects/pack/*.pack >packs-between &&
	test_line_count = 2 packs-between &&
	ls .git/objects/pack/loose-*.pack >loose-packs &&
	test_line_count = 1 loose-packs &&

	# The second run deletes loose objects
	# but does not create a pack-file.
	git maintenance run --task=loose-objects &&
	ls .git/objects >obj-dir-after &&
	cat >expect <<-\EOF &&
	info
	pack
	EOF
	test_cmp expect obj-dir-after &&
	ls .git/objects/pack/*.pack >packs-after &&
	test_cmp packs-between packs-after
'

test_expect_success 'maintenance.loose-objects.auto' '
	git repack -adk &&
	GIT_TRACE2_EVENT="$(pwd)/trace-lo1.txt" \
		git -c maintenance.loose-objects.auto=1 maintenance \
		run --auto --task=loose-objects 2>/dev/null &&
	test_subcommand ! git prune-packed --quiet <trace-lo1.txt &&
	printf data-A | git hash-object -t blob --stdin -w &&
	GIT_TRACE2_EVENT="$(pwd)/trace-loA" \
		git -c maintenance.loose-objects.auto=2 \
		maintenance run --auto --task=loose-objects 2>/dev/null &&
	test_subcommand ! git prune-packed --quiet <trace-loA &&
	printf data-B | git hash-object -t blob --stdin -w &&
	GIT_TRACE2_EVENT="$(pwd)/trace-loB" \
		git -c maintenance.loose-objects.auto=2 \
		maintenance run --auto --task=loose-objects 2>/dev/null &&
	test_subcommand git prune-packed --quiet <trace-loB &&
	GIT_TRACE2_EVENT="$(pwd)/trace-loC" \
		git -c maintenance.loose-objects.auto=2 \
		maintenance run --auto --task=loose-objects 2>/dev/null &&
	test_subcommand git prune-packed --quiet <trace-loC
'

test_expect_success 'incremental-repack task' '
	packDir=.git/objects/pack &&
	for i in $(test_seq 1 5)
	do
		test_commit $i || return 1
	done &&

	# Create three disjoint pack-files with size BIG, small, small.
	echo HEAD~2 | git pack-objects --revs $packDir/test-1 &&
	test_tick &&
	git pack-objects --revs $packDir/test-2 <<-\EOF &&
	HEAD~1
	^HEAD~2
	EOF
	test_tick &&
	git pack-objects --revs $packDir/test-3 <<-\EOF &&
	HEAD
	^HEAD~1
	EOF
	rm -f $packDir/pack-* &&
	rm -f $packDir/loose-* &&
	ls $packDir/*.pack >packs-before &&
	test_line_count = 3 packs-before &&

	# the job repacks the two into a new pack, but does not
	# delete the old ones.
	git maintenance run --task=incremental-repack &&
	ls $packDir/*.pack >packs-between &&
	test_line_count = 4 packs-between &&

	# the job deletes the two old packs, and does not write
	# a new one because the batch size is not high enough to
	# pack the largest pack-file.
	git maintenance run --task=incremental-repack &&
	ls .git/objects/pack/*.pack >packs-after &&
	test_line_count = 2 packs-after
'

test_expect_success EXPENSIVE 'incremental-repack 2g limit' '
	for i in $(test_seq 1 5)
	do
		test-tool genrandom foo$i $((512 * 1024 * 1024 + 1)) >>big ||
		return 1
	done &&
	git add big &&
	git commit -m "Add big file (1)" &&

	# ensure any possible loose objects are in a pack-file
	git maintenance run --task=loose-objects &&

	rm big &&
	for i in $(test_seq 6 10)
	do
		test-tool genrandom foo$i $((512 * 1024 * 1024 + 1)) >>big ||
		return 1
	done &&
	git add big &&
	git commit -m "Add big file (2)" &&

	# ensure any possible loose objects are in a pack-file
	git maintenance run --task=loose-objects &&

	# Now run the incremental-repack task and check the batch-size
	GIT_TRACE2_EVENT="$(pwd)/run-2g.txt" git maintenance run \
		--task=incremental-repack 2>/dev/null &&
	test_subcommand git multi-pack-index repack \
		 --no-progress --batch-size=2147483647 <run-2g.txt
'

test_expect_success 'maintenance.incremental-repack.auto' '
	git repack -adk &&
	git config core.multiPackIndex true &&
	git multi-pack-index write &&
	GIT_TRACE2_EVENT="$(pwd)/midx-init.txt" git \
		-c maintenance.incremental-repack.auto=1 \
		maintenance run --auto --task=incremental-repack 2>/dev/null &&
	test_subcommand ! git multi-pack-index write --no-progress <midx-init.txt &&
	test_commit A &&
	git pack-objects --revs .git/objects/pack/pack <<-\EOF &&
	HEAD
	^HEAD~1
	EOF
	GIT_TRACE2_EVENT=$(pwd)/trace-A git \
		-c maintenance.incremental-repack.auto=2 \
		maintenance run --auto --task=incremental-repack 2>/dev/null &&
	test_subcommand ! git multi-pack-index write --no-progress <trace-A &&
	test_commit B &&
	git pack-objects --revs .git/objects/pack/pack <<-\EOF &&
	HEAD
	^HEAD~1
	EOF
	GIT_TRACE2_EVENT=$(pwd)/trace-B git \
		-c maintenance.incremental-repack.auto=2 \
		maintenance run --auto --task=incremental-repack 2>/dev/null &&
	test_subcommand git multi-pack-index write --no-progress <trace-B
'

test_done
