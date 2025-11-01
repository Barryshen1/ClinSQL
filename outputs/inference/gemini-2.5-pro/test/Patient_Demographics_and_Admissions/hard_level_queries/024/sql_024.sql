WITH index_admissions AS (
    -- Step 1: Identify the specific cohort of index hospital admissions
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        ON a.hadm_id = d.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 76 AND 86
        AND a.insurance = 'Medicare'
        AND a.admission_location = 'EMERGENCY ROOM'
        AND d.seq_num = 1
        AND (
            (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%'))
            OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
        )
),
admission_sequences AS (
    -- Step 2: For each patient in the cohort, find their sequence of admissions to identify readmissions
    SELECT
        subject_id,
        hadm_id,
        admittime,
        -- Find the start time of the *next* admission for the same patient
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
    -- Optimization: Only process admissions for patients in our cohort
    WHERE subject_id IN (SELECT DISTINCT subject_id FROM index_admissions)
),
cohort_analysis AS (
    -- Step 3: Join index stays with readmission data and calculate per-stay metrics
    SELECT
        ia.subject_id,
        ia.hadm_id,
        ia.dischtime,
        s.next_admittime,
        -- Calculate the length of stay for the index admission in days
        DATETIME_DIFF(ia.dischtime, ia.admittime, HOUR) / 24.0 AS index_los_days,
        -- Flag if the index LOS was > 5 days
        CASE
            WHEN DATETIME_DIFF(ia.dischtime, ia.admittime, DAY) > 5 THEN 1
            ELSE 0
        END AS is_los_gt_5,
        -- Flag if readmitted within 30 days of discharge
        CASE
            WHEN DATETIME_DIFF(s.next_admittime, ia.dischtime, DAY) <= 30 THEN 1
            ELSE 0
        END AS is_readmitted_30d
    FROM
        index_admissions AS ia
    LEFT JOIN
        admission_sequences AS s
        ON ia.hadm_id = s.hadm_id
)
-- Step 4: Aggregate the results to answer the final questions
SELECT
    COUNT(hadm_id) AS total_index_admissions,
    -- Calculate 30-day all-cause readmission rate
    AVG(is_readmitted_30d) * 100 AS readmission_rate_30d,
    -- Calculate median index LOS for patients who were readmitted
    APPROX_QUANTILES(
        CASE WHEN is_readmitted_30d = 1 THEN index_los_days END, 100
    )[OFFSET(50)] AS median_los_readmitted,
    -- Calculate median index LOS for patients who were not readmitted
    APPROX_QUANTILES(
        CASE WHEN is_readmitted_30d = 0 THEN index_los_days END, 100
    )[OFFSET(50)] AS median_los_non_readmitted,
    -- Calculate the percentage of index stays with LOS > 5 days
    AVG(is_los_gt_5) * 100 AS percent_los_gt_5_days
FROM
    cohort_analysis;