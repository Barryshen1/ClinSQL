WITH stroke_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 78 AND 88
    AND pat.gender = 'F'
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 10 AND icd_code LIKE 'I63%') 
        OR (icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code LIKE '436%'))
    )
),

-- Critical lab events for stroke cohort within 72h
stroke_labs AS (
  SELECT 
    sc.hadm_id,
    COUNT(DISTINCT le.labevent_id) AS critical_lab_count
  FROM stroke_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN sc.admittime AND DATETIME_ADD(sc.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL  -- indicates abnormal value
  GROUP BY sc.hadm_id
),

-- General inpatient cohort (non-stroke, same age/gender)
general_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 78 AND 88
    AND pat.gender = 'F'
    AND adm.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 10 AND icd_code LIKE 'I63%') 
        OR (icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code LIKE '436%'))
    )
),

-- Critical lab events for general cohort within 72h
general_labs AS (
  SELECT 
    gc.hadm_id,
    COUNT(DISTINCT le.labevent_id) AS critical_lab_count
  FROM general_cohort gc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON gc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN gc.admittime AND DATETIME_ADD(gc.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL
  GROUP BY gc.hadm_id
)

-- Final output
SELECT 
  (SELECT MIN(critical_lab_count) FROM stroke_labs) AS min_72h_instability_score,
  (SELECT AVG(critical_lab_count) FROM stroke_labs) AS cohort_avg_critical_labs,
  (SELECT AVG(critical_lab_count) FROM general_labs) AS general_avg_critical_labs,
  (SELECT AVG(los_days) FROM stroke_cohort) AS cohort_avg_los,
  (SELECT AVG(hospital_expire_flag) FROM stroke_cohort) AS cohort_mortality_rate;