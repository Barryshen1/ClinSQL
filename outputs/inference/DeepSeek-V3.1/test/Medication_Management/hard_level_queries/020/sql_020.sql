WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 78 AND 88
        AND di.icd_code LIKE 'I46%'  -- Cardiac arrest ICD-10 codes
        AND di.icd_version = 10
),
meds AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        COUNT(DISTINCT pr.drug) AS unique_drugs,
        COUNT(DISTINCT CASE 
            WHEN LOWER(pr.drug) LIKE '%warfarin%' OR
                 LOWER(pr.drug) LIKE '%heparin%' OR
                 LOWER(pr.drug) LIKE '%enoxaparin%' OR
                 LOWER(pr.drug) LIKE '%dabigatran%' OR
                 LOWER(pr.drug) LIKE '%rivaroxaban%' OR
                 LOWER(pr.drug) LIKE '%apixaban%' OR
                 LOWER(pr.drug) LIKE '%insulin%' OR
                 LOWER(pr.drug) LIKE '%morphine%' OR
                 LOWER(pr.drug) LIKE '%fentanyl%' OR
                 LOWER(pr.drug) LIKE '%oxycodone%' OR
                 LOWER(pr.drug) LIKE '%hydromorphone%' OR
                 LOWER(pr.drug) LIKE '%methadone%' OR
                 LOWER(pr.drug) LIKE '%midazolam%' OR
                 LOWER(pr.drug) LIKE '%lorazepam%' OR
                 LOWER(pr.drug) LIKE '%diazepam%' OR
                 LOWER(pr.drug) LIKE '%propofol%'
            THEN pr.drug 
        END) AS high_risk_drugs,
        COUNT(DISTINCT pr.route) AS routes
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
    WHERE 
        pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    GROUP BY c.subject_id, c.hadm_id
),
scores AS (
    SELECT 
        c.*,
        COALESCE(m.unique_drugs, 0) + 2 * COALESCE(m.high_risk_drugs, 0) + COALESCE(m.routes, 0) AS complexity_score
    FROM cohort c
    LEFT JOIN meds m
        ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
),
tertiles AS (
    SELECT 
        *,
        NTILE(3) OVER (ORDER BY complexity_score) AS tertile
    FROM scores
),
readmissions AS (
    SELECT 
        t1.hadm_id,
        t1.dischtime,
        MIN(t2.admittime) AS readmit_time
    FROM tertiles t1
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` t2
        ON t1.subject_id = t2.subject_id
        AND t2.admittime > t1.dischtime
    GROUP BY t1.hadm_id, t1.dischtime
    HAVING DATETIME_DIFF(MIN(t2.admittime), t1.dischtime, DAY) <= 30
)
SELECT 
    tertile,
    COUNT(*) AS count,
    MIN(complexity_score) AS min_score,
    MAX(complexity_score) AS max_score,
    ROUND(AVG(los), 2) AS mean_los,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    ROUND(100.0 * COUNT(r.hadm_id) / COUNT(*), 2) AS readmission_30d_percent
FROM tertiles t
LEFT JOIN readmissions r
    ON t.hadm_id = r.hadm_id
GROUP BY tertile
ORDER BY tertile;