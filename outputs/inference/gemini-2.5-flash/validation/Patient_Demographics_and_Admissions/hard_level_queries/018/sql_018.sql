WITH initial_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        -- Calculate length of stay in days, cast to FLOAT64 for correct division
        CAST(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) AS FLOAT64) / 24.0 AS los
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
        ON adm.hadm_id = dicd.hadm_id AND adm.subject_id = dicd.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 58 AND 68
        AND adm.insurance = 'Medicare'
        AND adm.admission_type = 'EMERGENCY'
        AND dicd.seq_num = 1 -- Principal diagnosis
        -- Filter for femoral neck fracture ICD codes
        AND (
            -- ICD-9 codes for fracture of neck of femur (e.g., 820.0-820.9)
            (dicd.icd_version = 9 AND dicd.icd_code LIKE '820%')
            -- ICD-10 codes for fracture of neck of femur (e.g., S72.0XX)
            OR (dicd.icd_version = 10 AND dicd.icd_code LIKE 'S720%')
        )
        -- Exclude admissions with NULL dischtime, as LOS cannot be calculated
        AND adm.dischtime IS NOT NULL
),
-- Identify the readmission status for each initial admission
cohort_with_readmission_flag AS (
    SELECT
        ic.subject_id,
        ic.hadm_id,
        ic.admittime,
        ic.dischtime,
        ic.los,
        -- Determine if this admission is followed by a readmission within 30 days
        CASE
            WHEN LEAD(ic.admittime) OVER (PARTITION BY ic.subject_id ORDER BY ic.admittime) IS NOT NULL
                 AND DATETIME_DIFF(LEAD(ic.admittime) OVER (PARTITION BY ic.subject_id ORDER BY ic.admittime), ic.dischtime, DAY) <= 30
            THEN TRUE
            ELSE FALSE
        END AS is_readmitted_within_30_days
    FROM
        initial_cohort ic
)
-- Final aggregation to answer all parts of the clinical question
SELECT
    COUNT(DISTINCT c.hadm_id) AS total_initial_admissions,
    ROUND(COUNTIF(c.is_readmitted_within_30_days) * 100.0 / COUNT(DISTINCT c.hadm_id), 2) AS readmission_rate_percent,
    ROUND(
        (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM cohort_with_readmission_flag WHERE is_readmitted_within_30_days = TRUE),
    2) AS median_los_readmitted,
    ROUND(
        (SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] FROM cohort_with_readmission_flag WHERE is_readmitted_within_30_days = FALSE),
    2) AS median_los_non_readmitted,
    ROUND(COUNTIF(c.los > 8) * 100.0 / COUNT(DISTINCT c.hadm_id), 2) AS percent_stays_over_8_days
FROM
    cohort_with_readmission_flag c;