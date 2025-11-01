WITH cellulitis_codes AS (
    -- Step 1: Identify all ICD codes for 'cellulitis'.
    -- This makes the query robust to different ICD versions (9 or 10).
    SELECT
        icd_code,
        icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        LOWER(long_title) LIKE '%cellulitis%'
),

base_cohort AS (
    -- Step 2: Define the index cohort of interest based on patient and admission criteria.
    -- We select admissions that match the criteria and calculate their length of stay.
    SELECT DISTINCT -- Use DISTINCT to ensure each hadm_id is counted only once
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        -- Calculate length of stay in days for the index admission
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN
        cellulitis_codes AS cc
        ON dx.icd_code = cc.icd_code AND dx.icd_version = cc.icd_version
    WHERE
        -- Patient criteria
        pat.gender = 'F'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 55 AND 65
        -- Admission criteria
        AND adm.insurance = 'Medicare'
        AND adm.admission_location = 'EMERGENCY ROOM'
        -- Diagnosis criteria
        AND dx.seq_num = 1 -- Principal diagnosis
),

admissions_ranked AS (
    -- Step 3a: For each patient in our cohort, get all their hospital admissions and rank them chronologically.
    -- This is a necessary step to find the admission that *follows* our index admission.
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE
        subject_id IN (SELECT DISTINCT subject_id FROM base_cohort)
),

cohort_with_next_admission AS (
    -- Step 3b: Join the ranked admissions table to itself to find the next admission.
    -- Then, join with our base_cohort to filter for only our index stays.
    SELECT
        bc.hadm_id,
        bc.los_days,
        r1.dischtime,
        r2.admittime AS next_admittime,
        -- Calculate the time from discharge of the index stay to the start of the next admission.
        DATETIME_DIFF(r2.admittime, r1.dischtime, DAY) AS days_to_next_admission
    FROM
        base_cohort AS bc
    INNER JOIN
        admissions_ranked AS r1
        ON bc.hadm_id = r1.hadm_id
    LEFT JOIN -- Use a LEFT JOIN to include patients who were not readmitted
        admissions_ranked AS r2
        ON r1.subject_id = r2.subject_id AND r2.rn = r1.rn + 1
),

final_cohort_metrics AS (
    -- Step 4: Create a flag for 30-day readmission status.
    SELECT
        hadm_id,
        los_days,
        CASE
            WHEN days_to_next_admission IS NOT NULL AND days_to_next_admission <= 30 THEN 1
            ELSE 0
        END AS is_readmitted_30_days
    FROM
        cohort_with_next_admission
)

-- Step 5: Aggregate the results to calculate the final metrics.
SELECT
    -- 30-day readmission rate
    AVG(is_readmitted_30_days) * 100 AS readmission_rate_30_day_percent,

    -- Median index LOS for readmitted patients
    APPROX_QUANTILES(
        CASE WHEN is_readmitted_30_days = 1 THEN los_days END, 100 IGNORE NULLS
    )[OFFSET(50)] AS median_los_readmitted,

    -- Median index LOS for non-readmitted patients
    APPROX_QUANTILES(
        CASE WHEN is_readmitted_30_days = 0 THEN los_days END, 100 IGNORE NULLS
    )[OFFSET(50)] AS median_los_non_readmitted,

    -- Percent of index stays with LOS > 7 days
    AVG(CASE WHEN los_days > 7 THEN 1 ELSE 0 END) * 100 AS percent_los_gt_7_days
FROM
    final_cohort_metrics;