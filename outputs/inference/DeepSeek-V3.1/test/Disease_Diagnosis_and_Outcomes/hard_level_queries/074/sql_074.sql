WITH pe_patients AS (
    SELECT 
        p.subject_id, 
        p.anchor_age, 
        p.gender, 
        p.dod,
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        d.icd_code LIKE 'I26%'   -- Pulmonary embolism ICD-10
        AND p.gender = 'M'
        AND p.anchor_age BETWEEN 79 AND 89
),

comorbidity_count AS (
    SELECT 
        pp.subject_id,
        pp.hadm_id,
        pp.anchor_age,
        COUNT(DISTINCT SUBSTR(d.icd_code, 1, 3)) AS comorbidity_count
    FROM pe_patients pp
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON pp.hadm_id = d.hadm_id
    WHERE 
        d.icd_code NOT LIKE 'I26%'   -- Exclude PE itself
    GROUP BY pp.subject_id, pp.hadm_id, pp.anchor_age
),

q3_value AS (
    SELECT 
        APPROX_QUANTILES(comorbidity_count, 4)[OFFSET(3)] AS q3
    FROM comorbidity_count
),

comparison_group AS (
    SELECT 
        cc.subject_id,
        cc.hadm_id,
        cc.anchor_age,
        cc.comorbidity_count
    FROM comorbidity_count cc
    CROSS JOIN q3_value
    WHERE cc.comorbidity_count >= q3_value.q3
),

-- Define complications: cardiac and neurologic
complications AS (
    SELECT 
        cg.subject_id,
        cg.hadm_id,
        MAX(CASE WHEN d.icd_code LIKE 'I50%' OR d.icd_code LIKE 'I48%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%' THEN 1 ELSE 0 END) AS cardiac_complication,
        MAX(CASE WHEN d.icd_code LIKE 'G45%' OR d.icd_code LIKE 'G46%' OR d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' OR d.icd_code LIKE 'I65%' OR d.icd_code LIKE 'I66%' OR d.icd_code LIKE 'I67%' OR d.icd_code LIKE 'I68%' OR d.icd_code LIKE 'I69%' THEN 1 ELSE 0 END) AS neurologic_complication
    FROM comparison_group cg
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON cg.hadm_id = d.hadm_id
    GROUP BY cg.subject_id, cg.hadm_id
),

-- Survival days: for all patients (NULL if not deceased)
survival AS (
    SELECT 
        cg.subject_id,
        cg.hadm_id,
        CASE 
            WHEN p.dod IS NOT NULL THEN DATE_DIFF(CAST(p.dod AS DATE), CAST(a.admittime AS DATE), DAY)
            ELSE NULL 
        END AS survival_days
    FROM comparison_group cg
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON cg.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON cg.subject_id = p.subject_id
),

-- 30-day mortality: death within 30 days of admission
mortality_30d AS (
    SELECT 
        cg.subject_id,
        cg.hadm_id,
        CASE WHEN p.dod IS NOT NULL AND DATE_DIFF(CAST(p.dod AS DATE), CAST(a.admittime AS DATE), DAY) <= 30 THEN 1
             WHEN a.hospital_expire_flag = 1 AND DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) <= 30 THEN 1
             ELSE 0 
        END AS died_30d
    FROM comparison_group cg
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON cg.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON cg.subject_id = p.subject_id
),

-- Aggregate rates for comparison group
comparison_group_summary AS (
    SELECT 
        COUNT(*) AS total_patients,
        AVG(CAST(died_30d AS FLOAT64)) * 100 AS mortality_30d_rate,
        AVG(CAST(cardiac_complication AS FLOAT64)) * 100 AS cardiac_complication_rate,
        AVG(CAST(neurologic_complication AS FLOAT64)) * 100 AS neurologic_complication_rate,
        PERCENTILE_CONT(survival_days, 0.5) OVER() AS median_survival_days
    FROM comparison_group cg
    LEFT JOIN mortality_30d m ON cg.hadm_id = m.hadm_id
    LEFT JOIN complications c ON cg.hadm_id = c.hadm_id
    LEFT JOIN survival s ON cg.hadm_id = s.hadm_id
),

-- For the specific patient (84-year-old)
specific_patient AS (
    SELECT 
        cc.subject_id,
        cc.hadm_id,
        cc.comorbidity_count,
        PERCENT_RANK() OVER (ORDER BY cc.comorbidity_count) AS percentile_rank
    FROM comorbidity_count cc
    WHERE cc.anchor_age = 84
)

-- Final output
SELECT 
    sp.percentile_rank * 100 AS composite_risk_percentile,
    cgs.mortality_30d_rate,
    cgs.cardiac_complication_rate,
    cgs.neurologic_complication_rate,
    cgs.median_survival_days
FROM specific_patient sp
CROSS JOIN comparison_group_summary cgs;