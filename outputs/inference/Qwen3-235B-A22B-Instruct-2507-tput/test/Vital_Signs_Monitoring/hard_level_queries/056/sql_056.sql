SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.los,  -- <-- This is included
    ie.outtime,
    ce.charttime,
    di.label,
    ce.valuenum;