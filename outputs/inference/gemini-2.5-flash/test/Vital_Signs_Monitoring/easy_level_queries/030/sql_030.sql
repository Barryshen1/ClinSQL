WITH PatientHeartRateRanks AS (
    SELECT
        p.subject_id,
        icu.hadm_id,
        icu.stay_id,
        ce.charttime,
        ce.valuenum,
        ROW_NUMBER() OVER (PARTITION BY icu.stay_id ORDER BY ce.charttime ASC) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON p.subject_id = icu.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON icu.subject_id = ce.subject_id
        AND icu.hadm_id = ce.hadm_id
        AND icu.stay_id = ce.stay_id
    WHERE
        p.gender = 'F' -- Filter for female patients
        AND p.anchor_age BETWEEN 38 AND 48 -- Filter for age range 38-48
        AND ce.itemid = 220045 -- ItemID for Heart Rate (from d_items)
        AND ce.valuenum IS NOT NULL -- Ensure numeric value exists
        AND ce.valuenum > 0 -- Heart rate should be a positive value
)
SELECT
    MIN(phr.valuenum) AS min_first_recorded_heart_rate
FROM
    PatientHeartRateRanks phr
WHERE
    phr.rn = 1;