-- Boosts the priority of jobs of the selected types
--@module = true
--[====[

prioritize
==========

The prioritize script sets the ``do_now`` flag on all of the specified types of
jobs that are currently ready to be picked up by a dwarf. This will force them
to complete those jobs as soon as possible. This script can also continue to
monitor creation of new jobs and automatically boost the priority of jobs of
the specified types.

This is most useful for ensuring important (but low-priority -- according to DF)
tasks don't get indefinitely ignored in busy forts. The list of monitored job
types is cleared whenever you load a new map, so you can add a line like the one
below to your onMapLoad.init file to ensure important job types are always
completed promptly in your forts::

    prioritize -a StoreItemInVehicle PullLever DestroyBuilding RemoveConstruction RecoverWounded FillPond DumpItem SlaughterAnimal

Also see the ``do-job-now`` `tweak` for adding a hotkey to the jobs screen that
can toggle the priority of specific individual jobs.

Usage::

    prioritize [<options>] [<job_type> ...]

Examples:

``prioritize``
    Prints out which job types are being automatically prioritized and how many
    jobs of each type we have prioritized since we started watching them.

``prioritize -j``
    Prints out the list of active job types that you can prioritize right now.

``prioritize ConstructBuilding DestroyBuilding``
    Prioritizes all current building construction and destruction jobs.

``prioritize -a StoreItemInVehicle``
    Prioritizes all current and future vehicle loading jobs.

Options:

:``-a``, ``--add``:
    Prioritize all current and future new jobs of the specified job types.
:``-d``, ``--delete``:
    Stop automatically prioritizing new jobs of the specified job types.
:``-h``, ``--help``:
    Show help text.
:``-j``, ``--jobs``:
    Print out how many jobs of each type there are. This is useful for
    discovering the types of the jobs which you can prioritize right now. If any
    job types are specified, only returns the current count for those types.
:``-q``, ``--quiet``:
    Suppress informational output (error messages are still printed).
:``-r``, ``--registry``:
    Print out the full list of valid job types.
]====]

local argparse = require('argparse')
local eventful = require('plugins.eventful')

-- set of job types that we are watching. this needs to be global so we don't
-- lose player-set state when the script is reparsed. Also a getter function
-- that can be mocked out by unit tests.
g_watched_job_types = g_watched_job_types or {}
function get_watched_job_types() return g_watched_job_types end

eventful.enableEvent(eventful.eventType.UNLOAD, 1)
eventful.enableEvent(eventful.eventType.JOB_INITIATED, 5)

local function boost_job_if_member(job, job_types)
    if job_types[job.job_type] and not job.flags.do_now then
        job.flags.do_now = true
        return true
    end
    return false
end

local function on_new_job(job)
    local watched_job_types = get_watched_job_types()
    if boost_job_if_member(job, watched_job_types) then
        watched_job_types[job.job_type] = watched_job_types[job.job_type] + 1
    end
end

local function has_elements(collection)
    for _,_ in pairs(collection) do return true end
    return false
end

local function clear_watched_job_types()
    local watched_job_types = get_watched_job_types()
    for job_type in pairs(watched_job_types) do
        watched_job_types[job_type] = nil
    end
    eventful.onUnload.prioritize = nil
    eventful.onJobInitiated.prioritize = nil
end

local function update_handlers()
    local watched_job_types = get_watched_job_types()
    if has_elements(watched_job_types) then
        eventful.onUnload.prioritize = clear_watched_job_types
        eventful.onJobInitiated.prioritize = on_new_job
    else
        clear_watched_job_types()
    end
end

local function status()
    local first = true
    local watched_job_types = get_watched_job_types()
    for k,v in pairs(watched_job_types) do
        if first then
            print('Automatically prioritized jobs:')
            first = false
        end
        print(('%d\t%s'):format(v, df.job_type[k]))
    end
    if first then print('Not automatically prioritizing any jobs.') end
end

-- encapsulate this in a function so unit tests can mock it out
function get_postings()
    return df.global.world.jobs.postings
end

local function for_all_live_postings(cb)
    for _,posting in ipairs(get_postings()) do
        if posting.job and not posting.flags.dead then
            cb(posting)
        end
    end
end

local function boost(job_types, quiet)
    local count = 0
    for_all_live_postings(
        function(posting)
            if boost_job_if_member(posting.job, job_types) then
                count = count + 1
            end
        end)
    if not quiet then
        print(('Prioritized %d job%s.'):format(count, count == 1 and '' or 's'))
    end
end

local function boost_and_watch(job_types, quiet)
    boost(job_types, quiet)
    local watched_job_types = get_watched_job_types()
    for job_type in pairs(job_types) do
        if watched_job_types[job_type] then
            if not quiet then
                print('Skipping already-watched type: '..df.job_type[job_type])
            end
        else
            watched_job_types[job_type] = 0
            if not quiet then
                print('Automatically prioritizing future jobs of type: ' ..
                    df.job_type[job_type])
            end
        end
    end
    update_handlers()
end

local function remove_watch(job_types, quiet)
    local watched_job_types = get_watched_job_types()
    for job_type in pairs(job_types) do
        if not watched_job_types[job_type] then
            if not quiet then
                print('Skipping unwatched type: ' .. df.job_type[job_type])
            end
        else
            watched_job_types[job_type] = nil
            if not quiet then
                print('No longer automatically prioritizing jobs of type: ' ..
                      df.job_type[job_type])
            end
        end
    end
    update_handlers()
end

local function print_current_jobs(job_types)
    local job_counts_by_type = {}
    local filtered = has_elements(job_types)
    for_all_live_postings(
        function(posting)
            local job_type = posting.job.job_type
            if filtered and not job_types[job_type] then return end
            if not job_counts_by_type[job_type] then
                job_counts_by_type[job_type] = 0
            end
            job_counts_by_type[job_type] = job_counts_by_type[job_type] + 1
        end)
    local first = true
    for k,v in pairs(job_counts_by_type) do
        if first then
            print('Current job counts by type:')
            first = false
        end
        print(('%d\t%s'):format(v, df.job_type[k]))
    end
    if first then print('No current jobs.') end
end

local function print_registry()
    print('Valid job types:')
    for k,v in ipairs(df.job_type) do
        if v and df.job_type[v] and v:find('^%u%l') then
            print('  ' .. v)
        end
    end
end

local function parse_commandline(args)
    local opts, action = {}, status
    local positionals = argparse.processArgsGetopt(args, {
            {'a', 'add', handler=function() action = boost_and_watch end},
            {'d', 'delete', handler=function() action = remove_watch end},
            {'h', 'help', handler=function() opts.help = true end},
            {'j', 'jobs', handler=function() action = print_current_jobs end},
            {'q', 'quiet', handler=function() opts.quiet = true end},
            {'r', 'registry', handler=function() action = print_registry end},
        })

    if positionals[1] == 'help' then opts.help = true end
    if opts.help then return opts end

    -- validate the specified job types and convert the list to a map
    local job_types = {}
    for _,jtype in ipairs(positionals) do
        if not df.job_type[jtype] then
            dfhack.printerr(('Ignoring unknown job type: "%s". Run' ..
               ' "prioritize -r" for a list of valid job types.'):format(jtype))
        else
            job_types[df.job_type[jtype]] = true
        end
    end
    opts.job_types = job_types

    if action == status and has_elements(job_types) then
        action = boost
    end
    opts.action = action

    return opts
end

if not dfhack_flags.module then
    -- main script
    local opts = parse_commandline({...})
    if opts.help then print(dfhack.script_help()) return end

    opts.action(opts.job_types, opts.quiet)
end

if dfhack.internal.IN_TEST then
    unit_test_hooks = {
        clear_watched_job_types=clear_watched_job_types,
        on_new_job=on_new_job,
        status=status,
        boost=boost,
        boost_and_watch=boost_and_watch,
        remove_watch=remove_watch,
        print_current_jobs=print_current_jobs,
        print_registry=print_registry,
        parse_commandline=parse_commandline,
    }
end