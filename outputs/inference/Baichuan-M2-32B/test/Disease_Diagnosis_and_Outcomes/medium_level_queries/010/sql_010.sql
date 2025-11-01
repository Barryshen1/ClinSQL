WITH eligible_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 78 AND 88
),
ami_admissions AS (
    SELECT DISTINCT
        e.subject_id,
        e.hadm_id
    FROM eligible_admissions e
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON e.hadm_id = d.hadm_id
    WHERE 
        (d.icd_version = 9 AND d.icd_code LIKE '410%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
),
excluded_conditions AS (
    SELECT 
        d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE 
        -- Shock (representative codes; expand in practice)
        (d.icd_version = 9 AND d.icd_code IN ('785.5', '458', 'R57', 'I46.0', 'R96.81', 'R55', 'R66', 'R56'))
        OR (d.icd_version = 10 AND d.icd_code IN ('R57', 'I46.0', 'R96.81', 'R55', 'R66', 'R56', 'J95', 'J98.4'))
        -- Respiratory failure (representative codes; expand in practice)
        OR (d.icd_version = 9 AND d.icd_code IN ('518.81', '518.9'))
        OR (d.icd_version = 10 AND d.icd_code IN ('J95', 'J98.4'))
),
final_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.los_days,
        a.hospital_expire_flag
    FROM ami_admissions a
    LEFT JOIN excluded_conditions e 
        ON a.hadm_id = e.hadm_id
    WHERE e.hadm_id IS NULL
),
charlson_mapping AS (
    SELECT 
        icd_code,
        icd_version,
        weight
    FROM UNNEST([
        ('410%', 9, 1),   -- Myocardial infarction
        ('414.01', 9, 1), -- Heart failure
        ('496', 9, 1),    -- Chronic pulmonary disease
        ('272.4', 9, 1),  -- Connective tissue disease
        ('348.3', 9, 1),  -- Peptic ulcer disease
        ('585.1', 9, 1),  -- CKD
        ('250%', 9, 1),   -- Diabetes
        ('398.91', 9, 1), -- Peripheral vascular
        ('I21%', 10, 1),  -- Myocardial infarction
        ('I50.9', 10, 1), -- Heart failure
        ('J44.9', 10, 1), -- Chronic pulmonary
        ('M32.9', 10, 1), -- Connective tissue
        ('K25.9', 10, 1), -- Peptic ulcer
        ('N18', 10, 1),   -- CKD
        ('E11', 10, 1),   -- Diabetes
        ('I73.9', 10, 1)  -- Peripheral vascular
    ]) AS t(icd_code, icd_version, weight)
),
admission_diagnoses AS (
    SELECT 
        d.hadm_id,
        d.icd_code,
        d.icd_version,
        cm.weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN charlson_mapping cm 
        ON d.icd_version = cm.icd_version 
        AND (d.icd_code LIKE cm.icd_code OR d.icd_code = cm.icd_code)
),
charlson_scores AS (
    SELECT 
        hadm_id,
        SUM(weight) AS charlson_score
    FROM admission_diagnoses
    GROUP BY hadm_id
),
ami_flag AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN (icd_version=9 AND icd_code LIKE '410%') OR (icd_version=10 AND icd_code LIKE 'I21%') THEN 1 ELSE 0 END) AS has_ami
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
adjusted_charlson AS (
    SELECT 
        c.hadm_id,
        c.charlson_score - (a.has_ami * 1) AS adjusted_charlson_score
    FROM charlson_scores c
    LEFT JOIN ami_flag a ON c.hadm_id = a.hadm_id
),
comorbidity_groups AS (
    SELECT 
        hadm_id,
        CASE 
            WHEN adjusted_charlson_score = 0 THEN 'low'
            WHEN adjusted_charlson_score BETWEEN 1 AND 2 THEN 'medium'
            WHEN adjusted_charlson_score >= 3 THEN 'high'
        END AS comorbidity_burden
    FROM adjusted_charlson
),
ckd_diabetes_flags AS (
    SELECT 
        d.hadm_id,
        MAX(CASE WHEN 
            (d.icd_version=9 AND d.icd_code IN ('403.91','585.1','585.2','585.3','585.4','585.5','585.6','585.9')) 
            OR (d.icd_version=10 AND d.icd_code IN ('N18','N19','N25.1')) 
            THEN 1 ELSE 0 END) AS has_ckd,
        MAX(CASE WHEN 
            (d.icd_version=9 AND d.icd_code LIKE '250%') 
            OR (d.icd_version=10 AND d.icd_code LIKE 'E10%') 
            THEN 1 ELSE 0 END) AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    GROUP BY d.hadm_id
),
combined AS (
    SELECT 
        f.hadm_id,
        f.los_days,
        f.hospital_expire_flag,
        c.comorbidity_burden,
        cf.has_ckd,
        cf.has_diabetes
    FROM final_admissions f
    INNER JOIN comorbidity_groups c ON f.hadm_id = c.hadm_id
    INNER JOIN ckd_diabetes_flags cf ON f.hadm_id = cf.hadm_id
),
los_quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY los_days) AS los_quartile
    FROM combined
),
grouped AS (
    SELECT 
        los_quartile,
        comorbidity_burden,
        COUNT(*) AS n,
        SUM(hospital_expire_flag) AS deaths,
        AVG(has_ckd) AS ckd_prevalence,
        AVG(has_diabetes) AS diabetes_prevalence
    FROM los_quartiles
    GROUP BY los_quartile, comorbidity_burden
),
final_result AS (
    SELECT 
        los_quartile,
        comorbidity_burden,
        n,
        deaths,
        deaths / n AS mortality_rate,
        -- 95% CI for proportion
        SQRT(deaths / n * (1 - deaths / n) / n) * 1.96 AS ci_half_width,
        ckd_prevalence,
        diabetes_prevalence
    FROM grouped
)
SELECT * FROM final_result;