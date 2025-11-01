WITH all_admissions_with_next AS (
    -- For each admission, find the datetime of the next admission for the same patient
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
),

cohort AS (
    -- Identify the initial cohort of admissions based on patient demographics and principal diagnosis
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        -- Patient filters
        pat.gender = 'M'
        AND ((EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age) BETWEEN 50 AND 60
        -- Admission filters
        AND adm.insurance = 'Medicare'
        AND adm.admission_location = 'EMERGENCY ROOM'
        -- Principal diagnosis filter for Lower GI Bleeding (ICD-9 and ICD-10)
        AND dx.seq_num = 1
        AND dx.icd_code IN (
            'K92.1',  -- Melena (ICD-10)
            'K92.2',  -- Gastrointestinal hemorrhage, unspecified (ICD-10)
            'K62.5',  -- Hemorrhage of anus and rectum (ICD-10)
            '578.1',  -- Blood in stool (ICD-9)
            '578.9',  -- Hemorrhage of gastrointestinal tract, unspecified (ICD-9)
            '569.3'   -- Hemorrhage of rectum and anus (ICD-9)
        )
),

cohort_with_outcomes AS (
    -- For the cohort, calculate LOS and determine 30-day readmission status
    SELECT
        c.hadm_id,
        -- Flag as 1 if readmitted within 30 days of discharge, otherwise 0
        CASE
            WHEN a.next_admittime IS NOT NULL AND DATETIME_DIFF(a.next_admittime, c.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS is_readmitted_30d,
        -- Calculate length of stay in days
        DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
    FROM
        cohort AS c
    JOIN
        all_admissions_with_next AS a
        ON c.hadm_id = a.hadm_id
)

-- Final aggregation to calculate the requested metrics
SELECT
    AVG(is_readmitted_30d) * 100 AS readmission_rate_30d,
    APPROX_QUANTILES(CASE WHEN is_readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
    APPROX_QUANTILES(CASE WHEN is_readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_not_readmitted,
    AVG(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) * 100 AS percent_los_gt_6_days
FROM
    cohort_with_outcomes;