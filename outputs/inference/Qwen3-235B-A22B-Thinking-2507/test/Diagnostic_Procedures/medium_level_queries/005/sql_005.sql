WITH stroke_diagnoses AS (
    SELECT 
        di.hadm_id,
        di.seq_num
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE 
        LOWER(dd.long_title) LIKE '%ischemic stroke%'
        OR LOWER(dd.long_title) LIKE '%cerebral infarction%'
),
admissions_of_interest AS (
    SELECT 
        a.hadm_id,
        -- Calculate age at admission using MIMIC-IV anchor methodology
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        -- Calculate length of stay in days (using date difference, not datetime)
        DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days,
        -- Get minimum sequence number for stroke diagnosis in this admission
        MIN(sd.seq_num) AS min_stroke_seq
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN stroke_diagnoses sd 
        ON a.hadm_id = sd.hadm_id
    WHERE
        p.gender = 'F'
        AND a.dischtime IS NOT NULL  -- Ensure we have discharge time
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
    GROUP BY a.hadm_id, p.anchor_age, p.anchor_year, a.admittime, a.dischtime
),
procedure_counts AS (
    SELECT 
        hadm_id,
        COUNT(*) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY hadm_id
),
admission_stats AS (
    SELECT 
        aio.hadm_id,
        aio.los_days,
        CASE 
            WHEN aio.min_stroke_seq = 1 THEN 'primary'
            ELSE 'secondary'
        END AS diagnosis_type,
        COALESCE(pc.num_procedures, 0) AS num_procedures
    FROM admissions_of_interest aio
    LEFT JOIN procedure_counts pc 
        ON aio.hadm_id = pc.hadm_id
    WHERE
        aio.los_days BETWEEN 1 AND 8  -- Only include stays of 1-8 days
)
SELECT
    CASE 
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS stay_duration_group,
    diagnosis_type,
    AVG(num_procedures) AS mean_procedures,
    MIN(num_procedures) AS min_procedures,
    MAX(num_procedures) AS max_procedures,
    COUNT(*) AS num_admissions
FROM admission_stats
GROUP BY stay_duration_group, diagnosis_type
ORDER BY stay_duration_group, diagnosis_type;