WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 40 AND 50
        AND diag.icd_code = 'D70.0'
        AND diag.icd_version = 10
),

med_score AS (
    SELECT 
        c.hadm_id,
        COUNT(DISTINCT p.drug) AS complexity_score
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id AND c.subject_id = p.subject_id
    WHERE p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    GROUP BY c.hadm_id
),

quartiles AS (
    SELECT 
        hadm_id,
        complexity_score,
        NTILE(4) OVER (ORDER BY complexity_score) AS quartile
    FROM med_score
),

readmissions AS (
    SELECT 
        c1.hadm_id,
        COUNT(DISTINCT c2.hadm_id) > 0 AS readmit_30d
    FROM cohort c1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` c2
        ON c1.subject_id = c2.subject_id
        AND c2.admittime > c1.dischtime
        AND c2.admittime <= DATETIME_ADD(c1.dischtime, INTERVAL 30 DAY)
    GROUP BY c1.hadm_id
)

SELECT 
    q.quartile,
    COUNT(DISTINCT q.hadm_id) AS patient_count,
    AVG(ms.complexity_score) AS mean_score,
    MIN(ms.complexity_score) AS min_score,
    MAX(ms.complexity_score) AS max_score,
    AVG(c.los_days) AS mean_los,
    AVG(CAST(c.hospital_expire_flag AS INT)) * 100 AS mortality_pct,
    AVG(CAST(r.readmit_30d AS INT)) * 100 AS readmit_30d_pct
FROM quartiles q
INNER JOIN med_score ms ON q.hadm_id = ms.hadm_id
INNER JOIN cohort c ON q.hadm_id = c.hadm_id
LEFT JOIN readmissions r ON q.hadm_id = r.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;