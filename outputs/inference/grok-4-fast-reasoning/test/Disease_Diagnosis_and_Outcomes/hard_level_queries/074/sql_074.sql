WITH patients AS (
  SELECT subject_id, anchor_age, dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 79 AND 89
),
pe_admissions AS (
  SELECT DISTINCT
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.icd_version = 10 AND d.icd_code LIKE 'I26%'
),
base_cohort AS (
  SELECT 
    pa.subject_id, 
    pa.hadm_id, 
    pa.admittime, 
    pa.dischtime, 
    pa.deathtime,
    COUNT(DISTINCT di.icd_code) AS num_diagnoses
  FROM pe_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id AND di.icd_version = 10
  GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.deathtime
),
cohort AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM base_cohort
),
first_pe AS (
  SELECT subject_id, hadm_id, admittime, dischtime, deathtime, num_diagnoses, anchor_age, dod
  FROM cohort 
  INNER JOIN patients USING (subject_id)
  WHERE rn = 1
),
q75 AS (
  SELECT APPROX_QUANTILES(num_diagnoses, 4)[OFFSET(3)] AS q75_num_dx
  FROM first_pe
),
high_comorb_cohort AS (
  SELECT *
  FROM first_pe
  CROSS JOIN q75
  WHERE num_diagnoses >= q75_num_dx
),
mortality_flags AS (
  SELECT 
    hc.*,
    CASE 
      WHEN deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY) THEN 1
      WHEN dod IS NOT NULL AND deathtime IS NULL 
           AND DATE(dod) >= DATE(admittime) 
           AND DATE(dod) <= DATE(TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)) THEN 1
      ELSE 0 
    END AS died_30d,
    CASE 
      WHEN COALESCE(deathtime, dod) IS NOT NULL 
      THEN DATE_DIFF(COALESCE(DATE(deathtime), dod), DATE(admittime), DAY)
      ELSE NULL 
    END AS days_to_death
  FROM high_comorb_cohort hc
),
complication_flags AS (
  SELECT 
    mf.subject_id,
    mf.died_30d,
    mf.days_to_death,
    mf.anchor_age,
    MAX(CASE 
      WHEN di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' 
           OR di.icd_code LIKE 'I50%' 
           OR di.icd_code LIKE 'I47%' OR di.icd_code LIKE 'I48%' OR di.icd_code LIKE 'I49%' 
      THEN 1 ELSE 0 
    END) AS has_cardiac,
    MAX(CASE 
      WHEN di.icd_code LIKE 'I63%' OR di.icd_code = 'G45.9' 
      THEN 1 ELSE 0 
    END) AS has_neuro
  FROM mortality_flags mf
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON mf.hadm_id = di.hadm_id AND di.icd_version = 10
  GROUP BY mf.subject_id, mf.died_30d, mf.days_to_death, mf.anchor_age
)
SELECT 
  COUNT(*) AS cohort_size,
  ROUND(AVG(died_30d) * 100, 2) AS mortality_30d_pct,
  ROUND(AVG(has_cardiac) * 100, 2) AS cardiac_compl_rate_pct,
  ROUND(AVG(has_neuro) * 100, 2) AS neuro_compl_rate_pct,
  ROUND(APPROX_QUANTILES(days_to_death, 100)[OFFSET(50)], 0) AS median_survival_days,
  ROUND((COUNTIF(anchor_age <= 84) * 100.0 / COUNT(*)), 2) AS risk_score_percentile
FROM complication_flags;