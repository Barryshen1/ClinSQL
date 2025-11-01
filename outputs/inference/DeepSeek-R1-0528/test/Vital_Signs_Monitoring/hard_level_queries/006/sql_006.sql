WITH ugib_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code IN ('5780', '5781', '5789')) OR
    (icd_version = 10 AND icd_code IN ('K920', 'K921', 'K922'))
  )
),

cohort_ugib AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  INNER JOIN ugib_admissions ON ie.hadm_id = ugib_admissions.hadm_id
  WHERE 
    pat.gender = 'M' 
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 60 AND 70
),

vitals_ugib AS (
  SELECT 
    ce.stay_id,
    ce.itemid,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_ugib c
    ON ce.stay_id = c.stay_id
  WHERE 
    ce.itemid IN (220045, 220181, 220210)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),

counts_ugib AS (
  SELECT 
    stay_id,
    COUNTIF(itemid = 220045 AND valuenum > 100) AS tachycardia_count,
    COUNTIF(itemid = 220181 AND valuenum < 65) AS hypotension_count,
    COUNTIF(itemid = 220210 AND valuenum > 20) AS tachypnea_count
  FROM vitals_ugib
  GROUP BY stay_id
),

ugib_with_index AS (
  SELECT 
    c.stay_id,
    COALESCE(tachycardia_count, 0) + 
    COALESCE(hypotension_count, 0) + 
    COALESCE(tachypnea_count, 0) AS vital_instability_index,
    cu.los,
    cu.hospital_expire_flag
  FROM cohort_ugib cu
  LEFT JOIN counts_ugib c
    ON cu.stay_id = c.stay_id
),

percentiles AS (
  SELECT 
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(95)] AS ugib_p95,
    APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(90)] AS ugib_p90
  FROM ugib_with_index
),

top_decile_ugib AS (
  SELECT 
    stay_id,
    vital_instability_index,
    los,
    hospital_expire_flag
  FROM ugib_with_index, percentiles
  WHERE vital_instability_index >= ugib_p90
),

cohort_control AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M' 
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 60 AND 70
    AND ie.hadm_id NOT IN (SELECT hadm_id FROM ugib_admissions)
),

vitals_control AS (
  SELECT 
    ce.stay_id,
    ce.itemid,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_control c
    ON ce.stay_id = c.stay_id
  WHERE 
    ce.itemid IN (220045, 220181, 220210)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),

counts_control AS (
  SELECT 
    stay_id,
    COUNTIF(itemid = 220045 AND valuenum > 100) AS tachycardia_count,
    COUNTIF(itemid = 220181 AND valuenum < 65) AS hypotension_count,
    COUNTIF(itemid = 220210 AND valuenum > 20) AS tachypnea_count
  FROM vitals_control
  GROUP BY stay_id
),

control_with_counts AS (
  SELECT 
    cc.stay_id,
    COALESCE(c.tachycardia_count, 0) AS tachycardia_count,
    COALESCE(c.hypotension_count, 0) AS hypotension_count,
    COALESCE(c.tachypnea_count, 0) AS tachypnea_count,
    cc.los,
    cc.hospital_expire_flag
  FROM cohort_control cc
  LEFT JOIN counts_control c
    ON cc.stay_id = c.stay_id
),

comparison AS (
  SELECT 
    'Top Decile UGIB' AS group_label,
    AVG(tachycardia_count) AS avg_tachycardia,
    AVG(hypotension_count) AS avg_hypotension,
    AVG(tachypnea_count) AS avg_tachypnea,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM top_decile_ugib
  INNER JOIN counts_ugib USING (stay_id)
  
  UNION ALL
  
  SELECT 
    'Control' AS group_label,
    AVG(tachycardia_count) AS avg_tachycardia,
    AVG(hypotension_count) AS avg_hypotension,
    AVG(tachypnea_count) AS avg_tachypnea,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM control_with_counts
)

SELECT 
  '95th Percentile of Vital Instability Index' AS metric,
  (SELECT ugib_p95 FROM percentiles) AS value,
  NULL AS avg_tachycardia,
  NULL AS avg_hypotension,
  NULL AS avg_tachypnea,
  NULL AS avg_los,
  NULL AS mortality_rate
UNION ALL
SELECT 
  group_label AS metric,
  NULL AS value,
  avg_tachycardia,
  avg_hypotension,
  avg_tachypnea,
  avg_los,
  mortality_rate
FROM comparison;