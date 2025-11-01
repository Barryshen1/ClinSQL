WITH index_admissions AS (
    -- Step 1: Identify the cohort of index hospital admissions based on patient demographics,
    -- admission type, and principal diagnosis.
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'F'
        AND adm.insurance = 'Medicare'
        AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
        -- Calculate age at admission and filter for the 76-86 range
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 76 AND 86
        -- Filter for principal diagnosis of Acute Myocardial Infarction (AMI)
        AND dx.seq_num = 1
        AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I21%')
        )
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
),

patient_admissions_ranked AS (
    -- Step 2: For each patient in the cohort, find their next admission time.
    SELECT
        subject_id,
        hadm_id,
        admittime,
        -- Get the admission time of the next admission for this patient
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE subject_id IN (SELECT DISTINCT subject_id FROM index_admissions)
),

cohort_with_metrics AS (
    -- Step 3: Join index admissions with their next admission data to calculate LOS
    -- and determine if a 30-day readmission occurred.
    SELECT
        ia.hadm_id,
        -- Calculate the length of stay in days for the index admission
        DATETIME_DIFF(ia.dischtime, ia.admittime, DAY) AS los_days,
        -- Flag as 1 if a readmission occurred within 30 days of discharge, otherwise 0
        CASE
            WHEN par.next_admittime IS NOT NULL
            AND par.next_admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
            THEN 1
            ELSE 0
        END AS is_readmitted_30_days
    FROM index_admissions AS ia
    JOIN patient_admissions_ranked AS par
        ON ia.hadm_id = par.hadm_id
)

-- Step 4: Aggregate the results to calculate the final metrics.
SELECT
    -- Calculate the 30-day readmission rate as a percentage.
    AVG(is_readmitted_30_days) * 100.0 AS thirty_day_readmission_rate,

    -- Calculate the median LOS for patients who were readmitted.
    -- The IF function effectively filters for the readmitted group (NULLs are ignored by APPROX_QUANTILES).
    APPROX_QUANTILES(IF(is_readmitted_30_days = 1, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmitted,

    -- Calculate the median LOS for patients who were not readmitted.
    APPROX_QUANTILES(IF(is_readmitted_30_days = 0, los_days, NULL), 100)[OFFSET(50)] AS median_los_not_readmitted,

    -- Calculate the percentage of index stays that were longer than 4 days.
    AVG(IF(los_days > 4, 1.0, 0.0)) * 100.0 AS percent_index_stays_gt_4_days

FROM cohort_with_metrics;