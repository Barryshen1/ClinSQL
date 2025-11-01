WITH eligible_admissions AS (
    SELECT DISTINCT
        a.hadm_id, 
        a.subject_id, 
        a.admittime, 
        a.dischtime,
        DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 42 AND 52
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
            WHERE d.hadm_id = a.hadm_id 
                AND d.subject_id = a.subject_id
                AND d.icd_code = 'K31.80'
                AND d.icd_version = 10
        )
        AND DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) BETWEEN 1 AND 7
),
admission_dates AS (
    SELECT hadm_id, subject_id, admittime, dischtime
    FROM eligible_admissions
),
diagnostic_procedures AS (
    SELECT 
        p.hadm_id,
        p.subject_id,
        COUNT(*) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    INNER JOIN admission_dates a 
        ON p.hadm_id = a.hadm_id AND p.subject_id = a.subject_id
    WHERE 
        p.chartdate BETWEEN DATE(a.admittime) AND DATE(a.dischtime)
        AND (d.long_title LIKE '%diagnostic%' OR 
             d.long_title LIKE '%imaging%' OR 
             d.long_title LIKE '%scan%' OR 
             d.long_title LIKE '%echo%' OR 
             d.long_title LIKE '%endoscopy%' OR 
             d.long_title LIKE '%ultrasound%' OR 
             d.long_title LIKE '%CT%' OR 
             d.long_title LIKE '%MRI%' OR 
             d.long_title LIKE '%X-ray%')
    GROUP BY p.hadm_id, p.subject_id
)
SELECT 
    CASE 
        WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    COUNT(DISTINCT a.subject_id) AS patient_count,
    AVG(IFNULL(dp.num_procedures, 0)) AS mean_procedures,
    MIN(IFNULL(dp.num_procedures, 0)) AS min_procedures,
    MAX(IFNULL(dp.num_procedures, 0)) AS max_procedures
FROM eligible_admissions a
LEFT JOIN diagnostic_procedures dp 
    ON a.hadm_id = dp.hadm_id AND a.subject_id = dp.subject_id
GROUP BY los_group
ORDER BY los_group;