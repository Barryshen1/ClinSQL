WITH hhs_cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (dd.long_title LIKE '%hyperosmolar hyperglycemic state%' 
         OR dd.long_title LIKE '%hyperosmolar hyperglycemic syndrome%'
         OR dd.long_title LIKE '%hyperosmolarity with hyperglycemia%')
    AND i.intime = (SELECT MIN(i2.intime) 
                    FROM `physionet-data.mimiciv_3_1_icu.icustays` i2 
                    WHERE i2.hadm_id = a.hadm_id) -- first ICU stay per admission
),

critical_labs AS (
  SELECT 
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT CONCAT(CAST(l.itemid AS STRING), '-', CAST(l.charttime AS STRING))) AS num_critical_labs
  FROM hhs_cohort h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON h.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN h.intime AND TIMESTAMP_ADD(h.intime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL
  GROUP BY h.subject_id, h.hadm_id
),

percentile_calc AS (
  SELECT 
    PERCENTILE_CONT(num_critical_labs, 0.75) AS p75
  FROM critical_labs
),

high_instability_hhs AS (
  SELECT 
    cl.*,
    h.los,
    h.hospital_expire_flag
  FROM critical_labs cl
  INNER JOIN hhs_cohort h
    ON cl.hadm_id = h.hadm_id
  CROSS JOIN percentile_calc p
  WHERE cl.num_critical_labs >= p.p75
),

general_inpatients AS (
  SELECT 
    p.subject_id, 
    p.hadm_id,
    i.stay_id,
    i.intime,
    COUNT(DISTINCT CONCAT(CAST(l.itemid AS STRING), '-', CAST(l.charttime AS STRING))) AS num_critical_labs
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
      AND l.flag IS NOT NULL
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hadm_id NOT IN (SELECT hadm_id FROM hhs_cohort) -- exclude HHS patients
    AND i.intime = (SELECT MIN(i2.intime) 
                    FROM `physionet-data.mimiciv_3_1_icu.icustays` i2 
                    WHERE i2.hadm_id = a.hadm_id)
  GROUP BY p.subject_id, p.hadm_id, i.stay_id, i.intime
)

SELECT 
  (SELECT p75 FROM percentile_calc) AS threshold_75th_percentile,
  (SELECT COUNT(*) FROM high_instability_hhs) AS num_high_instability_admissions,
  (SELECT AVG(hospital_expire_flag) FROM high_instability_hhs) AS mortality_rate,
  (SELECT AVG(los) FROM high_instability_hhs) AS mean_los_days,
  (SELECT AVG(num_critical_labs) FROM high_instability_hhs) AS avg_critical_labs_high_instability,
  (SELECT AVG(num_critical_labs) FROM general_inpatients) AS avg_critical_labs_general_inpatients;