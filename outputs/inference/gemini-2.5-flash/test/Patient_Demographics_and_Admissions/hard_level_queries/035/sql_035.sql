WITH CohortAdmissions AS (
    -- CTE 1: Identify all potential index admissions based on demographic,
    -- admission specifics, and principal diagnosis.
    -- Also, pre-calculate the next admission time for each patient.
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age AS age_at_admission,
        -- Find the next admission for each subject (if any)
        LEAD(adm.admittime) OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
        AND adm.subject_id = diag.subject_id
    WHERE
        pat.gender = 'M'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 68 AND 78
        AND adm.admission_location = 'SKILLED NURSING FACILITY (SNF)'
        AND adm.insurance = 'Medicare'
        AND diag.seq_num = 1 -- Principal diagnosis (primary diagnosis)
        -- ICD-9 599.0: Urinary tract infection, site unspecified
        -- ICD-10 N39.0: Urinary tract infection, site unspecified
        AND diag.icd_code IN ('5990', 'N390')
),
CohortWithReadmissionStatus AS (
    -- CTE 2: Determine readmission status for each admission in the cohort
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        c.los_days,
        c.age_at_admission,
        c.next_admittime,
        -- Determine 30-day readmission status for patients discharged alive
        CASE
            WHEN c.hospital_expire_flag = 0  -- Patient must be discharged alive
            AND c.next_admittime IS NOT NULL
            AND DATE_DIFF(c.next_admittime, c.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmitted_30_day_flag
    FROM CohortAdmissions c
)
SELECT
    -- 1. 30-day readmission rate
    -- Use NULLIF to prevent division by zero if no patients were discharged alive
    ROUND(SAFE_DIVIDE(SUM(CASE WHEN cws.readmitted_30_day_flag = 1 THEN 1 ELSE 0 END) * 100.0, COUNTIF(cws.hospital_expire_flag = 0)), 2) AS readmission_rate_30_day_percent,

    -- 2. Median index LOS for readmitted vs non-readmitted
    -- Using BigQuery's APPROX_QUANTILES for median, which is often efficient for descriptive statistics.
    (SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(50)] FROM CohortWithReadmissionStatus WHERE readmitted_30_day_flag = 1) AS median_los_readmitted_days,
    (SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(50)] FROM CohortWithReadmissionStatus WHERE readmitted_30_day_flag = 0 AND hospital_expire_flag = 0) AS median_los_non_readmitted_days,

    -- 3. Percent of stays > 6 days (overall for the cohort)
    -- Use NULLIF to prevent division by zero if the cohort is empty
    ROUND(SAFE_DIVIDE(COUNTIF(cws.los_days > 6) * 100.0, COUNT(*)), 2) AS percent_of_stays_gt_6_days
FROM
    CohortWithReadmissionStatus cws;