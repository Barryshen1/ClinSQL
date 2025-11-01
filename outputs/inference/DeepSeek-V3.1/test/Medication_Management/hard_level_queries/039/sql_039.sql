WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 87 AND 97
        AND diag.icd_version = 10
        AND diag.icd_code IN ('I60', 'I61', 'I62')
),
medications AS (
    SELECT 
        emar.hadm_id,
        COUNT(DISTINCT CONCAT(emar.medication, COALESCE(ed.route, ''))) AS complexity_score
    FROM `physionet-data.mimiciv_3_1_hosp.emar` emar
    INNER JOIN cohort
        ON emar.hadm_id = cohort.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
        ON emar.emar_id = ed.emar_id
        AND emar.emar_seq = ed.emar_seq
    WHERE 
        emar.charttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 48 HOUR)
    GROUP BY emar.hadm_id
),
cohort_with_complexity AS (
    SELECT 
        c.*,
        COALESCE(m.complexity_score, 0) AS complexity_score,
        NTILE(4) OVER (ORDER BY COALESCE(m.complexity_score, 0)) AS complexity_quartile
    FROM cohort c
    LEFT JOIN medications m
        ON c.hadm_id = m.hadm_id
),
readmissions AS (
    SELECT 
        c1.hadm_id,
        COUNT(CASE WHEN c2.hadm_id IS NOT NULL THEN 1 ELSE NULL END) AS has_30d_readmit
    FROM cohort_with_complexity c1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` c2
        ON c1.subject_id = c2.subject_id
        AND c2.admittime > c1.dischtime
        AND c2.admittime <= DATETIME_ADD(c1.dischtime, INTERVAL 30 DAY)
    GROUP BY c1.hadm_id
)
SELECT 
    complexity_quartile,
    COUNT(*) AS admissions,
    MIN(complexity_score) AS min_score,
    MAX(complexity_score) AS max_score,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    ROUND(100.0 * SUM(has_30d_readmit) / COUNT(*), 2) AS readmit_30d_percent
FROM cohort_with_complexity c
LEFT JOIN readmissions r
    ON c.hadm_id = r.hadm_id
GROUP BY complexity_quartile
ORDER BY complexity_quartile;