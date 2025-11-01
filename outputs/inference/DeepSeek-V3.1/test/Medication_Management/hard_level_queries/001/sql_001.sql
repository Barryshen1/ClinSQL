WITH cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        COUNT(DISTINCT pr.drug) AS med_complexity_score
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON a.hadm_id = pr.hadm_id
        AND pr.starttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 7 DAY)
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 76 AND 86
        AND (d.icd_code = '427.5' AND diag.icd_version = 9
             OR d.icd_code LIKE 'I46%' AND diag.icd_version = 10)
    GROUP BY p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

cohort_with_quintile AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY med_complexity_score) AS quintile
    FROM cohort
),

readmission_flag AS (
    SELECT 
        c.*,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
                WHERE a2.subject_id = c.subject_id 
                AND a2.admittime > c.dischtime 
                AND a2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
            ) THEN 1
            ELSE 0 
        END AS readmission_30d
    FROM cohort_with_quintile c
    WHERE c.hospital_expire_flag = 0  -- only consider survivors for readmission
)

SELECT 
    quintile,
    COUNT(*) AS patient_count,
    AVG(med_complexity_score) AS avg_score,
    MIN(med_complexity_score) AS min_score,
    MAX(med_complexity_score) AS max_score,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    AVG(readmission_30d) * 100 AS readmission_30d_percent
FROM readmission_flag
GROUP BY quintile
ORDER BY quintile;