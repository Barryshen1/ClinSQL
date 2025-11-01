WITH patients_cohort AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 63 AND 73
),
icustays_cohort AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN patients_cohort p ON icu.subject_id = p.subject_id
),
status_epilepticus AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Status epilepticus%'
),
cohort AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM icustays_cohort icu
  JOIN status_epilepticus se ON icu.hadm_id = se.hadm_id
),
vital_signs AS (
  SELECT c.stay_id, ce.charttime, ce.itemid, ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  AND ce.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label IN ('Heart Rate', 'Mean Blood Pressure'))
),
vital_instability AS (
  SELECT stay_id, 
         AVG(CASE WHEN itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Heart Rate') THEN valuenum END) AS avg_hr,
         AVG(CASE WHEN itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Mean Blood Pressure') THEN valuenum END) AS avg_map
  FROM vital_signs
  GROUP BY stay_id
),
metrics AS (
  SELECT c.stay_id,
         ABS(v.avg_hr - 80) + ABS(v.avg_map - 65) AS vital_instability_index,
         SUM(CASE WHEN ce.itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Heart Rate') AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_burden,
         SUM(CASE WHEN ce.itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Mean Blood Pressure') AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_lt_65_burden,
         TIMESTAMP_DIFF(icu.outtime, icu.intime, HOUR) AS icu_los,
         a.hospital_expire_flag AS hospital_mortality
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.stay_id = icu.stay_id
  JOIN vital_signs ce ON c.stay_id = ce.stay_id
  JOIN vital_instability v ON c.stay_id = v.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  GROUP BY c.stay_id, v.avg_hr, v.avg_map, icu.outtime, icu.intime, a.hospital_expire_flag
)
SELECT 
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(25)] AS p25_vital_instability,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(50)] AS p50_vital_instability,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(75)] AS p75_vital_instability,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(90)] AS p90_vital_instability,
  AVG(vital_instability_index) AS mean_vital_instability,
  AVG(tachycardia_burden) AS mean_tachycardia_burden,
  AVG(map_lt_65_burden) AS mean_map_lt_65_burden,
  AVG(icu_los) AS mean_icu_los,
  SUM(hospital_mortality) / COUNT(*) AS hospital_mortality_rate
FROM metrics;