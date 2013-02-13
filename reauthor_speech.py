import sys
import os
import subprocess
try:
    import simplejson as json
except:
    import json
import sys

from radiotool.composer import Composition, Speech, Segment
print >> sys.stderr, "Composer imported"

from breath_classifier import breath_classifier
print >> sys.stderr, "Breath classifier imported"

class EditGroup:
    def __init__(self, start, end, edit_index):
        self.start = start
        self.end = end
        self.edit_index = edit_index

class Pause(EditGroup):
    def __init__(self, start, end, new_length, edit_index, generic=False):
        EditGroup.__init__(self, start, end, edit_index)
        self.new_length = new_length
        self.generic = generic

def rebuild_audio(speech, alignment, edits, **kwargs):
    cut_to_zc = kwargs.pop('cut_to_zc', True)
    out_file = kwargs.pop('out_file', 'out')
    samplerate = kwargs.pop('samplerate', 16000)
    crossfades = kwargs.pop('crossfades', True)
    fade_duration = 0.005

    cuts = []
    for i, word in enumerate(edits):
        start = round(word["start"], 5)
        end = round(word["end"], 5)
        
        if word["alignedWord"] == "sp" and "modifiedPause" in word:
            pause_len = round(word["pauseLength"], 5)
            cuts.append(Pause(start, end, pause_len, i))
        elif word["alignedWord"] == "gp":
            # handle generic pauses (room tone)
            print word
            pause_len = round(word["pauseLength"], 5)
            cuts.append(Pause(start, end, pause_len, i, generic=True))
        else:
            cuts.append(EditGroup(start, end, i))
    for i in range(len(alignment)):
        alignment[i]["start"] = round(alignment[i]["start"], 5)
        alignment[i]["end"] = round(alignment[i]["end"], 5)
        

    # break the cuts into cut groups
    # because we don't want to leave silence between adjacent words
    edit_groups = []
    new_group = True
    new_pause = False
    first = True
    align_idx = 0
    
    if isinstance(cuts[0], Pause):
        new_pause = True
        new_group = False
    
    for cut_idx, cut in enumerate(cuts):
        if not first:
            align_idx += 1
            if isinstance(cut, Pause):
                new_pause = True
            elif alignment[align_idx]["start"] != cut.start:
                new_group = True 
        else:
            first = False
        if new_group:
            align_idx = 0
            edit_groups.append(cut)
            while alignment[align_idx]["start"] < cut.start:
                align_idx += 1
            new_group = False
        if new_pause:
            edit_groups.append(cut)
            new_pause = False
            new_group = True

    print "edit groups start at", edit_groups

    # build the segments that correspond to the uncut segments of the speech
    segments = []
    composition_loc = 0.0
    tracks = []
    
    start_times = []
    
    c = Composition(channels=1)

    # new reauthoring loop
    for i, eg in enumerate(edit_groups):
        s = Speech(speech, "s" + str(i))
        c.add_track(s)

        if isinstance(eg, Pause):
            pause = eg
            start = pause.start
            end = pause.end
            pause_len = pause.new_length

            if cut_to_zc:
                try:
                    start = s.zero_crossing_before(start)
                except:
                    pass
                try:
                    end = s.zero_crossing_after(end)
                except:
                    pass

            start_times.append(composition_loc)
            
            gp_fade_dur = .2
            
            while pause_len > end - start:
                seg = Segment(s, composition_loc, start, end - start)
                c.add_score_segment(seg)
                c.fade_in(seg, gp_fade_dur)
                c.fade_out(seg, gp_fade_dur)
                composition_loc += (end - start) - gp_fade_dur 
                pause_len -= (end - start) - gp_fade_dur

            seg = Segment(s, composition_loc, start, pause_len)            
            c.add_score_segment(seg)
            c.fade_in(seg, fade_duration)
            c.fade_out(seg, fade_duration)
            composition_loc -= fade_duration
            composition_loc += pause_len
        else:
            start = eg.start
            if i + 1 < len(edit_groups):
                end = cuts[edit_groups[i + 1].edit_index - 1].end
            else:
                end = cuts[-1].end

            if cut_to_zc:
                try:
                    start = s.zero_crossing_before(start)
                except:
                    pass
                try:
                    end = s.zero_crossing_after(end)
                except:
                    pass

            seg = Segment(s, composition_loc, start, end - start)
            c.add_score_segment(seg)
            start_times.append(composition_loc)
            if crossfades:
                c.fade_in(seg, fade_duration)
                c.fade_out(seg, fade_duration)
                composition_loc -= fade_duration
            composition_loc += end - start

    
    # c.add_score_segments(segments)
    
    # for i in range(len(segments) - 1):
    #     c.cross_fade(segments[i], segments[i + 1], .05)
    #     #c.fade_out(segments[i], 1.0)
  
    c.output_score(
        adjust_dynamics=False,
        filename=out_file,
        channels=1,
        filetype='wav',
        samplerate=samplerate,
        separate_tracks=False)
    
        
    # return the start time of each word
    eg_idx = 0
    elapsed = 0.0
    timings = []
    for i, cut in enumerate(cuts):
        if eg_idx < len(edit_groups):
            if edit_groups[eg_idx].edit_index == cut.edit_index:
                elapsed = start_times[i]
        timings.append(round(elapsed, 5))
        if isinstance(cut, Pause):
            elapsed += cut.new_length
        else:
            elapsed += cut.end - cut.start
    return timings
    # return [(e.edit_index, start_times[i]) for i, e in enumerate(edit_groups)]


def render_pauses(speech_file, alignment):
    """and reauthor the alignment json"""
    pause_idx = 0
    subprocess.call('rm tmp/pauses/*.wav', shell=True)
    new_alignment = []
    for x in alignment:
        if x["alignedWord"] == "sp":
            comp = Composition(channels=1)
            speech = Speech(speech_file, "p")
            comp.add_track(speech)
            start = x["start"]
            end = x["end"]
            # ignore super-short pauses
            if end - start <= .05:
                new_alignment.append(x)
                pause_idx += 1
                continue
            # print "pause", pause_idx-1, "start:", start, "end", end
            # print "len", end - start
            seg = Segment(speech, 0.0, start, end - start)
            comp.add_score_segment(seg)
            comp.output_score(
                adjust_dynamics=False,
                filename="tmp/pauses/p%02d" % pause_idx,
                channels=1,
                filetype='wav',
                samplerate=speech.samplerate(),
                separate_tracks=False)
            print "# classifying p%02d.wav" % pause_idx
            print "# segment length:", x["end"] - x["start"]
            cls = breath_classifier.classify(
                'tmp/pauses/p%02d.wav' % pause_idx)
            for word in cls:
                word["start"] += x["start"]
                word["end"] += x["start"]
            cls[-1]["end"] = x["end"]
            new_alignment.extend(cls)
            pause_idx += 1
        else:
            new_alignment.append(x)
    return new_alignment


def render_pauses_as_one_track(speech_file, alignment):
    comp = Composition(channels=1)
    speech = Speech(speech_file, "p")
    comp.add_track(speech)
    comp_loc = 0.0
    fname = os.path.basename(speech_file)
    # subprocess.call('rm tmp/pauses/*.wav', shell=True)
    for x in alignment:
        if x["alignedWord"] == "sp":
            start = x["start"]
            end = x["end"]
            seg = Segment(speech, comp_loc, start, end - start)
            comp.add_score_segment(seg)
            comp_loc += (end - start)
    comp.output_score(
        adjust_dynamics=False,
        filename="tmp/pauses-%s" % fname.split('.')[0],
        channels=1,
        filetype='wav',
        samplerate=speech.samplerate(),
        separate_tracks=False)

def render_breaths_and_pauses(audio_file, alignment):
    comp = Composition(channels=1)
    comp_loc = 0
    pause_idx = 0
    breath_idx = 0
    for x in alignment:
        if x["alignedWord"] == "sp":
            audio = Speech(audio_file, "pause%02d" % pause_idx)
            pause_idx += 1
            comp.add_track(audio)
            start = x["start"]
            end = x["end"]
            seg = Segment(audio, comp_loc, start, end - start)
            comp.add_score_segment(seg)
            comp_loc += end - start
        elif x["alignedWord"] == "{BR}":
            audio = Speech(audio_file, "breath%02d" % breath_idx)
            breath_idx += 1
            comp.add_track(audio)
            start = x["start"]
            end = x["end"]
            seg = Segment(audio, comp_loc, start, end - start)
            comp.add_score_segment(seg)
            comp_loc += end - start
    comp.output_score(
        adjust_dynamics=False,
        filename="tmp/pb",
        channels=1,
        filetype='wav',
        samplerate=audio.samplerate(),
        separate_tracks=True)


def find_breaths(speech, alignment):
    breaths = []

    breath_threshold = .5
    
    import os
    import glob
    for wav_file in glob.glob('tmp/*.wav'):
        try:
            if os.path.isfile(wav_file):
                os.unlink(wav_file)
        except Exception, e:
            print e

    for i, word in enumerate(alignment[:-1]):
        if word["alignedWord"] == "sp":
            breaths.append(word)
        # if word["alignedWord"] == "sp" and\
        #     word["end"] - word["start"] > .5:
        #     breaths.append(word)
        # if word["word"].endswith(".") and\
        #     alignment[i + 1]["alignedWord"] == "sp":
        #     breaths.append(alignment[i + 1])

    for i, br in enumerate(breaths):
        s = Speech(speech, str(i))
        c = Composition(tracks=[s], channels=1)
        c.add_score_segment(
            Segment(s, 0.0, br["start"], br["end"] - br["start"])
        )
        c.output_score(
            adjust_dynamics=False,
            filename="tmp/%d" % i,
            channels=1,
            samplerate=16000
        )
        
    return breaths

if __name__ == '__main__':
    # speech_file = sys.argv[1]
    # alignment = sys.argv[2]
    # edits = sys.argv[3]
    # 
    # af = open(alignment, "r").read()
    # ef = open(edits, "r").read()
    # 
    # # json that represents the alignment of words to speech
    # alignment = json.loads(af)["words"]
    # 
    # # json that represents the words to delete
    # edits = json.loads(ef)["words"]
    # 
    # rebuild_audio(speech_file, alignment, edits, 
    #               cut_to_zc=True, out_file="out-zc")
    # rebuild_audio(speech_file, alignment, edits,
    #               cut_to_zc=False, out_file="out-nzc")
    
    # speech_file = sys.argv[1]
    # alignment = sys.argv[2]
    # af = open(alignment, "r").read()
    # alignment = json.loads(af)["words"]
    # 
    # find_breaths(speech_file, alignment)
    
    if sys.argv[1] == "write_breaths":
        speech_file = sys.argv[2]
        alignment = sys.argv[3]
        af = open(alignment, "r").read()
        alignment = json.loads(af)["words"]
        render_breaths_and_pauses(speech_file, alignment)
    elif sys.argv[1] == "pauses_sep":
        speech_file = sys.argv[2]
        alignment = sys.argv[3]
        af = open(alignment, "r").read()
        alignment = json.loads(af)["words"]
        render_pauses(speech_file, alignment)
    elif sys.argv[1] == "pauses":
        speech_file = sys.argv[2]
        alignment = sys.argv[3]
        af = open(alignment, "r").read()
        alignment = json.loads(af)["words"]
        render_pauses_as_one_track(speech_file, alignment)