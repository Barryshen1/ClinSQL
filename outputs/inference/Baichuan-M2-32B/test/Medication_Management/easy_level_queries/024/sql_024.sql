WITH cohort_admissions AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_year IS NOT NULL
        AND p.anchor_age IS NOT NULL
        AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 84 AND 94
),
antiplatelet_prescriptions AS (
    SELECT 
        p.subject_id, 
        p.hadm_id, 
        GREATEST(p.starttime, a.admittime) AS start_time,
        LEAST(p.stoptime, a.dischtime) AS end_time,
        p.drug,
        CASE 
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'aspirin') THEN 'aspirin'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'clopidogrel') THEN 'clopidogrel'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'ticagrelor') THEN 'ticagrelor'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'prasugrel') THEN 'prasugrel'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'cilostazol') THEN 'cilostazol'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'dipyridamole') THEN 'dipyridamole'
            WHEN REGEXP_CONTAINS(LOWER(p.drug), r'ticlopidine') THEN 'ticlopidine'
        END AS antiplatelet_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN cohort_admissions a 
        ON p.hadm_id = a.hadm_id
    WHERE REGEXP_CONTAINS(LOWER(p.drug), r'aspirin|clopidogrel|ticagrelor|prasugrel|cilostazol|dipyridamole|ticlopidine')
        AND p.starttime <= a.dischtime
        AND p.stoptime >= a.admittime
),
dapt_pairs AS (
    SELECT 
        ap1.subject_id,
        ap1.hadm_id,
        GREATEST(ap1.start_time, ap2.start_time) AS overlap_start,
        LEAST(ap1.end_time, ap2.end_time) AS overlap_end,
        TIMESTAMP_DIFF(LEAST(ap1.end_time, ap2.end_time), GREATEST(ap1.start_time, ap2.start_time), SECOND) AS duration_seconds
    FROM antiplatelet_prescriptions ap1
    JOIN antiplatelet_prescriptions ap2 
        ON ap1.subject_id = ap2.subject_id 
        AND ap1.hadm_id = ap2.hadm_id
        AND ap1.antiplatelet_class < ap2.antiplatelet_class
        AND GREATEST(ap1.start_time, ap2.start_time) < LEAST(ap1.end_time, ap2.end_time)
),
admission_max_durations AS (
    SELECT 
        subject_id,
        hadm_id,
        MAX(duration_seconds) AS max_duration_seconds
    FROM dapt_pairs
    GROUP BY subject_id, hadm_id
)
SELECT 
    MAX(max_duration_seconds) / 86400.0 AS max_duration_days
FROM admission_max_durations;