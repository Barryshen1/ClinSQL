WITH peak_k_per_stay AS (
    SELECT 
        ie.stay_id,
        MAX(le.valuenum) AS peak_k
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ie.hadm_id = le.hadm_id
        AND le.charttime >= ie.intime
        AND le.charttime <= ie.outtime
    WHERE p.gender = 'M'
        AND p.anchor_age = 56
        AND le.itemid = 50971  -- serum potassium
        AND le.valuenum IS NOT NULL
    GROUP BY ie.stay_id
)
SELECT 
    STDDEV(peak_k) AS std_dev_peak_k
FROM peak_k_per_stay;