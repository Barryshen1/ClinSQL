with actual subject_id for the target patient
WITH TARGET_PATIENT AS (
  SELECT 123456 AS subject_id
),

-- Number of distinct diagnoses per admission (as risk score) for ALL admissions
diagnosis_count AS (
    SELECT
        hadm_id,
        COUNT(DISTINCT icd_code) AS num_diagnoses
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),

-- High comorbidity threshold (75th percentile of num_diagnoses in all admissions)
comorbidity_threshold AS (
    SELECT
        APPROX_QUANTILES(num_diagnoses, 100)[OFFSET(75)] AS high_comorbidity_threshold
    FROM diagnosis_count
),

-- All male inpatients aged 71-81
male_71_81 AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 71 AND 81
),

-- DVT patients (ICD-9: 453.4x; ICD-10: I82.4, I82.5, I82.6, I82.8, I82.9)
dvt_patients AS (
    SELECT DISTINCT
        diag.subject_id,
        diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE (
        (diag.icd_version = 9 AND diag.icd_code LIKE '4534%')
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I82.4%')
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I82.5%')
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I82.6%')
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I82.8%')
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I82.9%')
    )
),

-- Cohort: male 71-81 with DVT and high comorbidity
cohort AS (
    SELECT
        m.subject_id,
        m.hadm_id,
        m.admittime,
        m.dischtime,
        m.deathtime,
        m.anchor_age,
        dc.num_diagnoses AS risk_score
    FROM male_71_81 m
    INNER JOIN dvt_patients dvt
        ON m.hadm_id = dvt.hadm_id
    INNER JOIN diagnosis_count dc
        ON m.hadm_id = dc.hadm_id
    WHERE dc.num_diagnoses >= (SELECT high_comorbidity_threshold FROM comorbidity_threshold)
),

-- 90-day mortality for cohort
cohort_mortality AS (
    SELECT
        hadm_id,
        CASE WHEN deathtime IS NOT NULL AND DATE_DIFF(deathtime, admittime, DAY) <= 90 THEN 1
            ELSE 0 END AS mortality_90day
    FROM cohort
),

-- Major complications (ICD-9: 998.*, 999.*; ICD-10: T81.*, T88.*)
major_complications AS (
    SELECT
        hadm_id,
        COUNT(*) AS comp_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (
        (icd_version = 9 AND (icd_code LIKE '998%' OR icd_code LIKE '999%'))
        OR (icd_version = 10 AND (icd_code LIKE 'T81%' OR icd_code LIKE 'T88%'))
    )
    GROUP BY hadm_id
),

-- General inpatient population (all admissions) for comparison
all_admissions AS (
    SELECT
        hadm_id,
        admittime,
        dischtime,
        deathtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Risk score distribution for percentile calculation
risk_distribution AS (
    SELECT
        subject_id,
        hadm_id,
        risk_score,
        PERCENT_RANK() OVER (ORDER BY risk_score) AS risk_percentile
    FROM cohort
)

-- Final output with aggregated results
SELECT
    APPROX_QUANTILES(c.risk_score, 100)[OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(c.risk_score, 100)[OFFSET(25)] AS q1_risk_score,
    APPROX_QUANTILES(c.risk_score, 100)[OFFSET(75)] AS q3_risk_score,
    AVG(cm.mortality_90day) * 100 AS mortality_90day_percent,
    AVG(CASE WHEN mc.comp_count > 0 THEN 1 ELSE 0 END) * 100 AS cohort_complication_rate,
    (SELECT AVG(CASE WHEN mc2.comp_count > 0 THEN 1 ELSE 0 END) * 100
     FROM all_admissions aa
     LEFT JOIN major_complications mc2 ON aa.hadm_id = mc2.hadm_id) AS all_complication_rate,
    AVG(CASE WHEN c.deathtime IS NULL THEN DATE_DIFF(c.dischtime, c.admittime, DAY) END) AS cohort_survivor_los,
    (SELECT AVG(CASE WHEN aa.deathtime IS NULL THEN DATE_DIFF(aa.dischtime, aa.admittime, DAY) END)
     FROM all_admissions aa) AS all_survivor_los,
    (SELECT risk_percentile 
     risk_distribution rd 
     JOIN TARGET_PATIENT tp ON rd.subject_id = tp.subject_id) AS patient_risk_percentile
FROM cohort c
LEFT JOIN cohort_mortality cm ON c.hadm_id = cm.hadm_id
LEFT JOIN major_complications mc ON c.hadm_id = mc.hadm_id;