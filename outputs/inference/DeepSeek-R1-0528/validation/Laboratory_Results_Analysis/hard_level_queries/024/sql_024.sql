WITH cohort_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code = '4275') OR
          (diag.icd_version = 10 AND diag.icd_code IN ('I462', 'I468', 'I469'))
        )
    )
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 53 AND 63
),

cohort_labs AS (
  SELECT 
    ca.hadm_id,
    CASE 
      WHEN le.itemid = 50813 AND le.valuenum > 4 THEN 1  -- Lactate > 4 mmol/L
      WHEN le.itemid = 50822 AND (le.valuenum < 3.0 OR le.valuenum > 6.0) THEN 1  -- Potassium
      WHEN le.itemid = 50824 AND (le.valuenum < 130 OR le.valuenum > 150) THEN 1  -- Sodium
      WHEN le.itemid = 50912 AND le.valuenum > 2.0 THEN 1  -- Creatinine > 2.0 mg/dL
      WHEN le.itemid = 50809 AND (le.valuenum < 50 OR le.valuenum > 400) THEN 1  -- Glucose
      WHEN le.itemid = 51222 AND le.valuenum < 7 THEN 1  -- Hemoglobin < 7 g/dL
      WHEN le.itemid IN (51300, 51301) AND (le.valuenum < 2 OR le.valuenum > 20) THEN 1  -- WBC
      ELSE 0
    END AS is_critical
  FROM cohort_admissions ca
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ca.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
  WHERE le.itemid IN (50813, 50822, 50824, 50912, 50809, 51222, 51300, 51301)
    AND le.valuenum IS NOT NULL
),

cohort_instability AS (
  SELECT 
    ca.hadm_id,
    COALESCE(SUM(cl.is_critical), 0) AS instability_score
  FROM cohort_admissions ca
  LEFT JOIN cohort_labs cl
    ON ca.hadm_id = cl.hadm_id
  GROUP BY ca.hadm_id
),

percentile_90 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM cohort_instability
),

high_instability_cohort AS (
  SELECT 
    ci.hadm_id,
    ci.instability_score,
    ca.hospital_expire_flag,
    DATETIME_DIFF(ca.dischtime, ca.admittime, DAY) AS los_days
  FROM cohort_instability ci
  INNER JOIN cohort_admissions ca
    ON ci.hadm_id = ca.hadm_id
  CROSS JOIN percentile_90
  WHERE ci.instability_score >= percentile_90.p90_score
),

all_admissions AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

all_labs AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN le.itemid = 50813 AND le.valuenum > 4 THEN 1
      WHEN le.itemid = 50822 AND (le.valuenum < 3.0 OR le.valuenum > 6.0) THEN 1
      WHEN le.itemid = 50824 AND (le.valuenum < 130 OR le.valuenum > 150) THEN 1
      WHEN le.itemid = 50912 AND le.valuenum > 2.0 THEN 1
      WHEN le.itemid = 50809 AND (le.valuenum < 50 OR le.valuenum > 400) THEN 1
      WHEN le.itemid = 51222 AND le.valuenum < 7 THEN 1
      WHEN le.itemid IN (51300, 51301) AND (le.valuenum < 2 OR le.valuenum > 20) THEN 1
      ELSE 0
    END AS is_critical
  FROM all_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
    AND le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
  WHERE le.itemid IN (50813, 50822, 50824, 50912, 50809, 51222, 51300, 51301)
    AND le.valuenum IS NOT NULL
),

all_instability AS (
  SELECT 
    a.hadm_id,
    COALESCE(SUM(al.is_critical), 0) AS instability_score
  FROM all_admissions a
  LEFT JOIN all_labs al
    ON a.hadm_id = al.hadm_id
  GROUP BY a.hadm_id
),

entire_pop_avg AS (
  SELECT AVG(instability_score) AS avg_entire_pop
  FROM all_instability
)

SELECT 
  (SELECT COUNT(*) FROM high_instability_cohort) AS patient_count,
  (SELECT SUM(hospital_expire_flag) FROM high_instability_cohort) AS mortality_count,
  (SELECT AVG(los_days) FROM high_instability_cohort) AS mean_los_days,
  (SELECT AVG(instability_score) FROM high_instability_cohort) AS avg_critical_labs_subgroup,
  (SELECT avg_entire_pop FROM entire_pop_avg) AS avg_critical_labs_entire_pop;