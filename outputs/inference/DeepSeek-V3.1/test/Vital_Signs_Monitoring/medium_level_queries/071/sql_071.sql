WITH female_icu_stays AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
),

spo2_data AS (
    SELECT 
        ce.stay_id,
        AVG(ce.valuenum) AS mean_spo2
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN female_icu_stays fis
        ON ce.stay_id = fis.stay_id
    WHERE ce.itemid = 220277  -- SpO2
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 0 AND 100  -- plausible range
    GROUP BY ce.stay_id
)

SELECT 
    COUNT(*) AS total_stays,
    SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END) AS stays_below_92,
    SAFE_DIVIDE(
        SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END),
        COUNT(*)
    ) AS percentile
FROM spo2_data;