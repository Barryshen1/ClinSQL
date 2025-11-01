WITH AdmissionsFiltered AS (
    -- Select admissions for males aged 52-62 with valid admission and discharge times
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        pat.gender,
        pat.anchor_age,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 52 AND 62
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
        AND adm.dischtime > adm.admittime
),
PrimaryAKIDiagnoses AS (
    -- Identify admissions with a primary diagnosis of Acute Kidney Injury (AKI)
    SELECT DISTINCT
        diag.subject_id,
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    WHERE
        diag.seq_num = 1 -- Primary diagnosis
        AND (
            (diag.icd_version = 9 AND diag.icd_code LIKE '584%') OR -- ICD-9: Acute kidney failure (584.x)
            (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')  -- ICD-10: Acute kidney failure (N17.x)
        )
)
-- Calculate the 75th percentile of hospital length of stay for the target population
SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY af.los_days) OVER() AS p75_hospital_los_days
FROM
    AdmissionsFiltered AS af
INNER JOIN
    PrimaryAKIDiagnoses AS pad
    ON af.subject_id = pad.subject_id AND af.hadm_id = pad.hadm_id;