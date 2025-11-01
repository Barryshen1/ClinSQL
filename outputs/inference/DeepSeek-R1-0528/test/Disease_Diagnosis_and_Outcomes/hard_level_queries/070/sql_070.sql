WITH base_cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id,
        a.admittime,
        p.dod,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
        AND a.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE 
                (icd_version = 9 AND icd_code LIKE '453%') OR
                (icd_version = 10 AND icd_code LIKE 'I82%')
        )
),
comorbidity AS (
    SELECT 
        bc.hadm_id,
        COUNT(DISTINCT di.icd_code) AS comorbidity_index
    FROM base_cohort bc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON bc.hadm_id = di.hadm_id
    GROUP BY bc.hadm_id
),
p75_value AS (
    SELECT 
        PERCENTILE_CONT(comorbidity_index, 0.75) AS p75
    FROM comorbidity
),
final_cohort AS (
    SELECT 
        c.hadm_id,
        bc.admittime,
        bc.dod,
        c.comorbidity_index
    FROM comorbidity c
    INNER JOIN base_cohort bc
        ON c.hadm_id = bc.hadm_id
    CROSS JOIN p75_value
    WHERE c.comorbidity_index >= p75_value.p75
),
complications AS (
    SELECT 
        fc.hadm_id,
        MAX(
            CASE WHEN 
                (di.icd_version = 9 AND di.icd_code LIKE '4151%') OR
                (di.icd_version = 10 AND di.icd_code LIKE 'I26%') OR
                (di.icd_version = 9 AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%')) OR
                (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')) OR
                (di.icd_version = 9 AND di.icd_code LIKE '578%') OR
                (di.icd_version = 10 AND di.icd_code IN ('K920', 'K921', 'K922'))
            THEN 1 ELSE 0 END
        ) AS has_complication
    FROM final_cohort fc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON fc.hadm_id = di.hadm_id
    GROUP BY fc.hadm_id
),
mortality AS (
    SELECT 
        hadm_id,
        CASE WHEN dod IS NOT NULL AND DATE_DIFF(CAST(dod AS DATE), CAST(admittime AS DATE), DAY) <= 30 
             THEN 1 ELSE 0 END AS died_30d
    FROM final_cohort
),
decedents_survival AS (
    SELECT 
        hadm_id,
        DATE_DIFF(CAST(dod AS DATE), CAST(admittime AS DATE), DAY) AS survival_days
    FROM final_cohort
    WHERE dod IS NOT NULL
),
quartiles_cte AS (
    SELECT 
        PERCENTILE_CONT(comorbidity_index, 0.25) AS q1,
        PERCENTILE_CONT(comorbidity_index, 0.5) AS median_com,
        PERCENTILE_CONT(comorbidity_index, 0.75) AS q3_com
    FROM final_cohort
)
SELECT
    COUNT(*) AS cohort_size,
    ROUND(AVG(CAST(m.died_30d AS FLOAT64)) * 100, 2) AS mortality_30d_rate,
    ROUND(AVG(CAST(cp.has_complication AS FLOAT64)) * 100, 2) AS complication_rate,
    (SELECT PERCENTILE_CONT(survival_days, 0.5) FROM decedents_survival) AS median_survival_days,
    q.q1 AS q1_composite,  -- Fixed: Changed q1_com to q1
    q.median_com AS median_composite,
    q.q3_com AS q3_composite
FROM final_cohort fc
LEFT JOIN mortality m ON fc.hadm_id = m.hadm_id
LEFT JOIN complications cp ON fc.hadm_id = cp.hadm_id
CROSS JOIN quartiles_cte q;