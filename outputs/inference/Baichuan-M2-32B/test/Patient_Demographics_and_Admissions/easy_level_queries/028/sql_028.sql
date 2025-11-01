WITH sepsis_admissions AS (
    SELECT DISTINCT
        d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON d.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 90 AND 100
        AND d.icd_version = 10
        AND d.icd_code IN ('R65.20', 'R65.21', 'R65.22', 'A41.9')
),
icu_stays_with_los AS (
    SELECT
        i.stay_id,
        TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN sepsis_admissions s
        ON i.hadm_id = s.hadm_id
    WHERE i.outtime IS NOT NULL  -- Exclude ongoing ICU stays
)
SELECT
    STDDEV_SAMP(los_days) AS std_dev_los
FROM icu_stays_with_los;