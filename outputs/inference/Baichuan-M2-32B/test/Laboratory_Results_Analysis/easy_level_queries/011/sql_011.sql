WITH patient_icu_stays AS (
    SELECT 
        p.subject_id,
        i.stay_id,
        i.intime,
        i.outtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON p.subject_id = i.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age = 56
),
potassium_per_stay AS (
    SELECT 
        p.subject_id,
        p.stay_id,
        MAX(l.valuenum) AS peak_potassium
    FROM patient_icu_stays p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON p.subject_id = l.subject_id
        AND l.charttime BETWEEN p.intime AND p.outtime
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
        ON l.itemid = d.itemid
    WHERE d.label LIKE '%potassium%'
        AND l.valueuom IN ('mEq/L', 'mmol/L')  -- moved to labevents and expanded units
        AND l.valuenum BETWEEN 1 AND 10  -- exclude implausible values
    GROUP BY p.subject_id, p.stay_id
)
SELECT 
    subject_id,
    STDDEV_SAMP(peak_potassium) AS potassium_stddev
FROM potassium_per_stay
GROUP BY subject_id;