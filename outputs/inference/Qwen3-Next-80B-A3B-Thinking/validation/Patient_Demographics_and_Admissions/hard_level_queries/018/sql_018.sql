WITH initial_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
        p.anchor_age,
        p.gender,
        d.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE d.seq_num = 1
      AND d.icd_code LIKE 'S72.0%'
      AND a.admission_location LIKE 'EMERGENCY ROOM%'
      AND a.insurance = 'Medicare'
      AND p.gender = 'F'
      AND p.anchor_age BETWEEN 58 AND 68
),
readmission_flags AS (
    SELECT 
        ia.*,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = ia.subject_id
              AND a2.hadm_id != ia.hadm_id
              AND a2.admittime >= ia.dischtime
              AND a2.admittime <= ia.dischtime + INTERVAL 30 DAY
        ) THEN 1 ELSE 0 END AS readmitted
    FROM initial_admissions ia
)
SELECT 
    CAST(SUM(readmitted) AS FLOAT64) / COUNT(*) AS readmission_rate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN readmitted = 1 THEN los END) AS median_los_readmitted,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN readmitted = 0 THEN los END) AS median_los_non_readmitted,
    SUM(CASE WHEN los > 8 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_los_gt_8
FROM readmission_flags;