WITH PatientDemographics AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 35 AND 45 -- Inclusive age range
),
StrokeAdmissions AS (
    SELECT DISTINCT
        di.subject_id,
        di.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        -- ICD-10 codes for Cerebrovascular diseases (stroke categories)
        (di.icd_version = 10 AND LEFT(di.icd_code, 3) BETWEEN 'I60' AND 'I69')
        -- ICD-9 codes for Cerebrovascular diseases (stroke categories)
        OR (di.icd_version = 9 AND LEFT(di.icd_code, 3) BETWEEN '430' AND '438')
)
SELECT
    PERCENTILE_CONT(icu.los, 0.5) OVER() AS median_icu_los_days
FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
JOIN
    PatientDemographics pd
    ON icu.subject_id = pd.subject_id
JOIN
    StrokeAdmissions sa
    ON icu.subject_id = sa.subject_id AND icu.hadm_id = sa.hadm_id;