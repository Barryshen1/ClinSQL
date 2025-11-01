WITH admissions_filtered AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.admission_type,
        adm.insurance,
        pat.gender,
        pat.anchor_age,
        -- Calculate LOS in days; ensure valid dates for calculation
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND adm.insurance = 'Medicare'
        AND pat.anchor_age BETWEEN 51 AND 61
        AND adm.admission_type = 'EMERGENCY'
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
),
principal_dx_pancreatitis AS (
    SELECT
        diag.subject_id,
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    WHERE
        diag.seq_num = 1 -- Principal diagnosis
        AND (
               (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%') -- ICD-10: K85.x Acute pancreatitis
            OR (diag.icd_version = 9 AND diag.icd_code = '5770')     -- ICD-9: 577.0 Acute pancreatitis
        )
),
cohort_admissions AS (
    -- Filter admissions for the specific cohort criteria
    SELECT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime,
        af.los_days
    FROM
        admissions_filtered AS af
    INNER JOIN
        principal_dx_pancreatitis AS pdx
        ON af.subject_id = pdx.subject_id AND af.hadm_id = pdx.hadm_id
),
readmission_status AS (
    -- Determine the next admission time for each patient to check for readmission
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.los_days,
        LEAD(ca.admittime) OVER (PARTITION BY ca.subject_id ORDER BY ca.admittime) AS next_admittime
    FROM
        cohort_admissions AS ca
),
final_cohort_with_readmission AS (
    -- Tag each admission as readmitted or not within 30 days
    SELECT
        rs.subject_id,
        rs.hadm_id,
        rs.admittime,
        rs.dischtime,
        rs.los_days,
        CASE
            WHEN rs.next_admittime IS NOT NULL
            AND DATE_DIFF(rs.next_admittime, rs.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmitted_30_day
    FROM
        readmission_status AS rs
)
-- Final aggregation to calculate the required metrics
SELECT
    COUNT(f.hadm_id) AS total_index_admissions,
    COUNTIF(f.readmitted_30_day = 1) AS readmitted_count,
    SAFE_DIVIDE(COUNTIF(f.readmitted_30_day = 1) * 100.0, COUNT(f.hadm_id)) AS readmission_rate_percent,

    -- Median LOS for readmitted patients
    (SELECT PERCENTILE_CONT(los_days, 0.5) OVER() FROM final_cohort_with_readmission WHERE readmitted_30_day = 1) AS median_los_readmitted,
    -- Median LOS for non-readmitted patients
    (SELECT PERCENTILE_CONT(los_days, 0.5) OVER() FROM final_cohort_with_readmission WHERE readmitted_30_day = 0) AS median_los_non_readmitted,

    -- Percent stays > 9 days for readmitted patients
    SAFE_DIVIDE(COUNTIF(f.readmitted_30_day = 1 AND f.los_days > 9) * 100.0, COUNTIF(f.readmitted_30_day = 1)) AS percent_gt_9_days_readmitted,
    -- Percent stays > 9 days for non-readmitted patients
    SAFE_DIVIDE(COUNTIF(f.readmitted_30_day = 0 AND f.los_days > 9) * 100.0, COUNTIF(f.readmitted_30_day = 0)) AS percent_gt_9_days_non_readmitted
FROM
    final_cohort_with_readmission AS f
LIMIT 1; -- Ensures a single row output for all aggregated metrics;