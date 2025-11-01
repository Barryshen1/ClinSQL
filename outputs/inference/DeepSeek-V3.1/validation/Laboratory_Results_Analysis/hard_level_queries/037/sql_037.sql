WITH cohort AS (
  SELECT DISTINCT
    adm.subject_id, 
    adm.hadm_id,
    -- Calculate LOS in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    adm.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE adm.hadm_id = diag.hadm_id
        AND diag.icd_version = 10
        AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%')
),

labs_first_48h AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    -- Count distinct abnormal lab events in first 48h
    COUNT(DISTINCT le.itemid) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
    AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL  -- Only flagged (abnormal) values
  GROUP BY adm.subject_id, adm.hadm_id
),

cohort_with_labs AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.los_days,
    c.mortality,
    COALESCE(l.lab_instability_score, 0) AS lab_instability_score
  FROM cohort c
  LEFT JOIN labs_first_48h l
    ON c.hadm_id = l.hadm_id
),

general_population_labs AS (
  SELECT 
    AVG(score) AS avg_general_score
  FROM (
    SELECT 
      adm.subject_id,
      adm.hadm_id,
      COUNT(DISTINCT le.itemid) AS score
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON adm.hadm_id = le.hadm_id
      AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR)
      AND le.flag IS NOT NULL
    GROUP BY adm.subject_id, adm.hadm_id
  )
)

SELECT 
  -- For the cohort: get the 25th percentile of lab instability score
  (SELECT approx_quantiles(lab_instability_score, 100)[OFFSET(25)] 
   FROM cohort_with_labs) AS percentile_25_score,
  AVG(los_days) AS mean_los_days,
  AVG(mortality) AS in_hospital_mortality_rate,
  -- For comparison
  (SELECT avg_general_score FROM general_population_labs) AS general_population_avg_score
FROM cohort_with_labs;