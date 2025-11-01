WITH ards_patients AS (
  SELECT DISTINCT diag.subject_id, diag.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON diag.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON diag.subject_id = p.subject_id
  WHERE d.long_title LIKE '%acute respiratory distress syndrome%'
    AND p.anchor_age BETWEEN 71 AND 81
    AND p.gender = 'M'
),

map_data AS (
  SELECT ce.stay_id, ce.valuenum AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN ards_patients ap ON ce.stay_id = ap.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON ce.stay_id = icu.stay_id
  WHERE ce.itemid IN (220052, 220181, 225312)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
),

instability_scores AS (
  SELECT stay_id, STDDEV(map_value) AS map_sd
  FROM map_data
  GROUP BY stay_id
),

percentile_90 AS (
  SELECT PERCENTILE_CONT(map_sd, 0.9) OVER() AS p90
  FROM instability_scores
  LIMIT 1
),

high_instability_patients AS (
  SELECT isc.stay_id, isc.map_sd
  FROM instability_scores isc
  CROSS JOIN percentile_90 p
  WHERE isc.map_sd >= p.p90
),

high_instability_outcomes AS (
  SELECT
    COUNT(DISTINCT ap.hadm_id) AS total_patients,
    SUM(adm.hospital_expire_flag) AS deaths,
    AVG(icu.los) AS mean_icu_los
  FROM high_instability_patients hip
  INNER JOIN ards_patients ap ON hip.stay_id = ap.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON ap.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ap.stay_id = icu.stay_id
),

ards_high_instability_labs AS (
  SELECT
    COUNT(*) AS total_labs,
    SUM(CASE WHEN le.valuenum > 2 THEN 1 ELSE 0 END) AS critical_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN ards_patients ap ON le.hadm_id = ap.hadm_id
  INNER JOIN high_instability_patients hip ON ap.stay_id = hip.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ap.stay_id = icu.stay_id
  WHERE le.itemid = 50813 -- lactate
    AND le.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
),

general_inpatients AS (
  SELECT DISTINCT icu.stay_id, icu.hadm_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

general_inpatient_labs AS (
  SELECT
    COUNT(*) AS total_labs,
    SUM(CASE WHEN le.valuenum > 2 THEN 1 ELSE 0 END) AS critical_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN general_inpatients gi ON le.hadm_id = gi.hadm_id
  WHERE le.itemid = 50813 -- lactate
    AND le.charttime BETWEEN gi.intime AND DATETIME_ADD(gi.intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
)

SELECT
  (SELECT p90 FROM percentile_90) AS instability_threshold,
  (SELECT total_patients FROM high_instability_outcomes) AS n_patients,
  (SELECT deaths FROM high_instability_outcomes) AS deaths,
  (SELECT deaths / total_patients FROM high_instability_outcomes) AS mortality_rate,
  (SELECT mean_icu_los FROM high_instability_outcomes) AS mean_icu_los,
  (SELECT critical_labs / total_labs FROM ards_high_instability_labs) AS ards_critical_lab_rate,
  (SELECT critical_labs / total_labs FROM general_inpatient_labs) AS general_critical_lab_rate;