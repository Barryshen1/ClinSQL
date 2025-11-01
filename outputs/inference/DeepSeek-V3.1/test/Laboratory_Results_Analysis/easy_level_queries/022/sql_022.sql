WITH male_icu_stays AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age = 63
),

peak_ph_per_stay AS (
    SELECT 
        mis.stay_id,
        MAX(ce.valuenum) AS peak_ph
    FROM male_icu_stays mis
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON mis.stay_id = ce.stay_id
    WHERE ce.itemid IN (780, 1126, 223830)  -- arterial pH itemids
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 6.8 AND 7.8  -- plausible pH range
    GROUP BY mis.stay_id
)

SELECT 
    APPROX_QUANTILES(peak_ph, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(peak_ph, 100)[OFFSET(75)] AS q3,
    APPROX_QUANTILES(peak_ph, 100)[OFFSET(75)] - APPROX_QUANTILES(peak_ph, 100)[OFFSET(25)] AS iqr
FROM peak_ph_per_stay;