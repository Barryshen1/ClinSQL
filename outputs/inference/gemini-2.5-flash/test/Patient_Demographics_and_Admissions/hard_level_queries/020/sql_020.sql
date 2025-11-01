with the next admission time
WITH all_patient_admissions AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.admission_type,
        ad.admission_location,
        ad.insurance,
        pa.gender,
        pa.anchor_age,
        -- Use LEAD window function to find the start time of the next admission for the same patient
        LEAD(ad.admittime) OVER (PARTITION BY pa.subject_id ORDER BY ad.admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
),
-- CTE to filter for the specific cohort and calculate readmission status and LOS
filtered_cohort AS (
    SELECT
        apa.subject_id,
        apa.hadm_id,
        apa.admittime,
        apa.dischtime,
        -- Calculate Length of Stay in days. Assumes dischtime is not null, enforced below.
        DATE_DIFF(apa.dischtime, apa.admittime, DAY) AS los_days,
        -- Determine if readmitted within 30 days.
        -- dischtime and next_admittime must be non-null for a valid comparison.
        CASE
            WHEN apa.dischtime IS NOT NULL
             AND apa.next_admittime IS NOT NULL
             AND DATE_DIFF(apa.next_admittime, apa.dischtime, DAY) <= 30 THEN 1
            ELSE 0
        END AS readmitted_30d
    FROM
        all_patient_admissions apa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON apa.hadm_id = di.hadm_id AND apa.subject_id = di.subject_id
    WHERE
        apa.gender = 'F'
        AND apa.anchor_age BETWEEN 76 AND 86
        AND apa.insurance = 'Medicare'
        AND apa.admission_location = 'TRANSFER FROM OTHER HOSPITAL'
        AND di.seq_num = 1 -- Principal diagnosis only
        AND (
            -- ICD-9 for AMI: 410.xx codes
            (di.icd_version = 9 AND di.icd_code LIKE '410%')
            OR
            -- ICD-10 for AMI: I21.xx codes
            (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
        )
        AND apa.dischtime IS NOT NULL -- Essential for accurate LOS and readmission calculation
)
-- Final SELECT statement to calculate the requested metrics from the filtered_cohort
SELECT
    -- 1. 30-day readmission rate as a percentage
    ROUND(SAFE_DIVIDE(CAST(SUM(fc.readmitted_30d) AS NUMERIC), COUNT(fc.hadm_id)) * 100, 2) AS readmission_rate_30d_percent,

    -- 2. Median index LOS for patients who were readmitted within 30 days
    (SELECT PERCENTILE_CONT(los_days, 0.5) FROM filtered_cohort WHERE readmitted_30d = 1) AS median_los_readmitted_days,

    -- 3. Median index LOS for patients who were NOT readmitted within 30 days
    (SELECT PERCENTILE_CONT(los_days, 0.5) FROM filtered_cohort WHERE readmitted_30d = 0) AS median_los_not_readmitted_days,

    -- 4. Percentage of index stays longer than 4 days
    ROUND(SAFE_DIVIDE(CAST(COUNTIF(fc.los_days > 4) AS NUMERIC), COUNT(fc.hadm_id)) * 100, 2) AS percent_stays_gt_4_days
FROM
    filtered_cohort fc;