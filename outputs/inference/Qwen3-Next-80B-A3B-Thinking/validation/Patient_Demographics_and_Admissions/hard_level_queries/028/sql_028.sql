WITH index_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        p.anchor_age,
        p.anchor_year,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
        a.admission_location,
        a.insurance,
        d_icd.long_title AS diagnosis
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
    WHERE 
        d.seq_num = 1
        AND p.gender = 'F'
        AND LOWER(a.insurance) = 'medicare'
        AND LOWER(a.admission_location) LIKE '%emergency room%'
        AND LOWER(d_icd.long_title) LIKE '%cellulitis%'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 55 AND 65
),
readmission_status AS (
    SELECT 
        i.hadm_id,
        i.dischtime,
        CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted,
        DATE_DIFF(i.dischtime, i.admittime, DAY) AS los
    FROM index_admissions i
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r
        ON i.subject_id = r.subject_id
        AND r.admittime > i.dischtime
        AND r.admittime <= DATE_ADD(i.dischtime, INTERVAL 30 DAY)
),
median_readmitted AS (
    SELECT
        PERCENTILE_CONT(0.5) OVER (ORDER BY los) AS median_los
    FROM readmission_status
    WHERE readmitted = 1
    LIMIT 1
),
median_non_readmitted AS (
    SELECT
        PERCENTILE_CONT(0.5) OVER (ORDER BY los) AS median_los
    FROM readmission_status
    WHERE readmitted = 0
    LIMIT 1
)
SELECT
    SUM(readmitted) / COUNT(*) AS readmission_rate,
    (SELECT median_los FROM median_readmitted) AS median_los_readmitted,
    (SELECT median_los FROM median_non_readmitted) AS median_los_non_readmitted,
    (SUM(CASE WHEN los > 7 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS percent_stays_gt_7_days
FROM readmission_status;