WITH all_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.admission_location,
        a.insurance,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        -- Calculate age at admission
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        -- Get next admission time for readmission calculation
        LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE a.dischtime IS NOT NULL  -- Only include discharged admissions
),
cohort AS (
    SELECT
        a.*
    FROM all_admissions a
    -- Join to get principal diagnosis (seq_num = 1)
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE 
        a.gender = 'M'
        AND a.age_at_admission BETWEEN 65 AND 75
        AND a.admission_location = 'EMERGENCY ROOM ADMIT'
        AND a.insurance = 'Medicare'
        AND di.seq_num = 1
        -- Filter for acute respiratory failure using specific ICD codes
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'J96.0%')
            OR (di.icd_version = 9 AND di.icd_code IN ('51881', '51882', '51884'))
        )
),
with_metrics AS (
    SELECT
        *,
        -- Flag for 30-day readmission
        CASE 
            WHEN next_admittime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY) THEN 1 
            ELSE 0 
        END AS readmitted_30d,
        -- Calculate LOS in days
        TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*60*60.0) AS los_days
    FROM cohort
)
SELECT
    (SUM(readmitted_30d) * 1.0 / COUNT(*)) AS readmission_rate,
    APPROX_QUANTILES(IF(readmitted_30d=1, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
    APPROX_QUANTILES(IF(readmitted_30d=0, los_days, NULL), 100)[OFFSET(50)] AS median_los_non_readmitted,
    (SUM(CASE WHEN los_days > 9 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percent_los_gt9
FROM with_metrics;