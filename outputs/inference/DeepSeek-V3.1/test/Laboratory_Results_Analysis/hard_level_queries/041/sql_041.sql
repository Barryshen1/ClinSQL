WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        -- Correct age calculation: anchor_age + years since anchor_year
        p.anchor_age + DATE_DIFF(DATE(a.admittime), DATE(p.anchor_year, 1, 1), YEAR) AS age_admit
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    WHERE 
        p.gender = 'M'
        -- Use specific ICD codes for heart failure instead of LIKE pattern
        AND diag.icd_code IN ('I50.2', 'I50.2', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 
                             'I50.3', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.4',
                             'I50.40', 'I50.41', 'I50.42', 'I50.43', '428.0', '428.1',
                             '428.2', '428.3', '428.4', '428.9')
        AND diag.icd_version IN (9, 10)
),
-- Filter cohort to age 54-64 at admission
cohort_filtered AS (
    SELECT *
    FROM cohort
    WHERE age_admit BETWEEN 54 AND 64
),
-- Get labs in first 48h for these patients
labs_48h AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        l.itemid,
        l.charttime,
        l.valuenum,
        l.ref_range_lower,
        l.ref_range_upper,
        -- Handle cases where reference ranges might be missing
        CASE 
            WHEN l.ref_range_lower IS NOT NULL AND l.ref_range_upper IS NOT NULL 
                 AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper) THEN 1
            ELSE 0 
        END AS is_abnormal
    FROM cohort_filtered c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON c.hadm_id = l.hadm_id
    WHERE 
        l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
        AND l.valuenum IS NOT NULL
),
-- Compute instability score: count of distinct abnormal lab tests per patient
instability_scores AS (
    SELECT 
        subject_id,
        hadm_id,
        COUNT(DISTINCT CASE WHEN is_abnormal = 1 THEN itemid END) AS score
    FROM labs_48h
    GROUP BY subject_id, hadm_id
),
-- Compute 95th percentile of score using APPROX_QUANTILES
percentile_score AS (
    SELECT 
        APPROX_QUANTILES(score, 100)[OFFSET(95)] AS p95
    FROM instability_scores
),
-- Label patients: high-score (>=p95) and control (<p95)
patient_groups AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.score,
        CASE WHEN i.score >= (SELECT p95 FROM percentile_score) THEN 1 ELSE 0 END AS is_high_score
    FROM instability_scores i
),
-- Count abnormal labs per patient
abnormal_lab_counts AS (
    SELECT 
        subject_id,
        hadm_id,
        COUNT(*) AS ab_count
    FROM labs_48h 
    WHERE is_abnormal = 1
    GROUP BY subject_id, hadm_id
)
-- Final output: for high-score group and control group
SELECT 
    pg.is_high_score,
    COUNT(*) AS num_patients,
    -- In-hospital mortality rate
    AVG(a.hospital_expire_flag) AS mortality_rate,
    -- Mean LOS in days
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los,
    -- Average number of abnormal lab events per patient (not distinct tests)
    AVG(COALESCE(alc.ab_count, 0)) AS mean_abnormal_labs_per_patient
FROM patient_groups pg
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pg.hadm_id = a.hadm_id
LEFT JOIN abnormal_lab_counts alc
    ON pg.hadm_id = alc.hadm_id AND pg.subject_id = alc.subject_id
GROUP BY pg.is_high_score;