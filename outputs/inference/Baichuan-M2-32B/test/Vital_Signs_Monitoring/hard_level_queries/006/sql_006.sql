WITH patients_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 60 AND 70
),
ugib_diagnoses AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('K25.0', 'K25.1', 'K25.8', 'K25.9') -- UGIB ICD-10 codes
),
icu_stays AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_admissions pa 
    ON i.subject_id = pa.subject_id AND i.hadm_id = pa.hadm_id
  JOIN ugib_diagnoses ud 
    ON i.subject_id = ud.subject_id AND i.hadm_id = ud.hadm_id
),
chartevents_hr AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS hr_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_stays i 
    ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
  WHERE ce.itemid = 211 -- Heart Rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
),
chartevents_map AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_stays i 
    ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
  WHERE ce.itemid = 456 -- MAP
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
),
chartevents_rr AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS rr_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_stays i 
    ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
  WHERE ce.itemid = 220 -- Respiratory Rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
),
abnormal_hr AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id,
    COUNT(*) AS hr_abnormal_count
  FROM chartevents_hr
  WHERE hr_value > 100
  GROUP BY subject_id, hadm_id, stay_id
),
abnormal_map AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id,
    COUNT(*) AS map_abnormal_count
  FROM chartevents_map
  WHERE map_value < 65
  GROUP BY subject_id, hadm_id, stay_id
),
abnormal_rr AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id,
    COUNT(*) AS rr_abnormal_count
  FROM chartevents_rr
  WHERE rr_value > 20
  GROUP BY subject_id, hadm_id, stay_id
),
instability_per_stay AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id,
    COALESCE(hr.hr_abnormal_count, 0) + 
    COALESCE(map.map_abnormal_count, 0) + 
    COALESCE(rr.rr_abnormal_count, 0) AS instability_index
  FROM icu_stays i
  LEFT JOIN abnormal_hr hr 
    ON i.subject_id = hr.subject_id AND i.hadm_id = hr.hadm_id AND i.stay_id = hr.stay_id
  LEFT JOIN abnormal_map map 
    ON i.subject_id = map.subject_id AND i.hadm_id = map.hadm_id AND i.stay_id = map.stay_id
  LEFT JOIN abnormal_rr rr 
    ON i.subject_id = rr.subject_id AND i.hadm_id = rr.hadm_id AND i.stay_id = rr.stay_id
),
percentile_95 AS (
  SELECT 
    APPROX_QUANTILES(instability_index, 100)[OFFSET(95)] AS p95
  FROM instability_per_stay
)
SELECT * FROM percentile_95;

/* Part 2: Comparison for top decile UGIB vs controls */
WITH 
  patients_admissions AS (
    SELECT 
      p.subject_id, 
      a.hadm_id, 
      a.admittime,
      a.hospital_expire_flag,
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age,
      p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 60 AND 70
  ),
  ugib_diagnoses AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN ('K25.0', 'K25.1', 'K25.8', 'K25.9') -- UGIB ICD-10 codes
  ),
  icu_stays AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id, 
      i.intime,
      i.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN patients_admissions pa 
      ON i.subject_id = pa.subject_id AND i.hadm_id = pa.hadm_id
    JOIN ugib_diagnoses ud 
      ON i.subject_id = ud.subject_id AND i.hadm_id = ud.hadm_id
  ),
  chartevents_hr AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS hr_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN icu_stays i 
      ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
    WHERE ce.itemid = 211 
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  ),
  chartevents_map AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS map_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN icu_stays i 
      ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
    WHERE ce.itemid = 456 
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  ),
  chartevents_rr AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS rr_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN icu_stays i 
      ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
    WHERE ce.itemid = 220 
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  ),
  abnormal_hr AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      COUNT(*) AS hr_abnormal_count
    FROM chartevents_hr
    WHERE hr_value > 100
    GROUP BY subject_id, hadm_id, stay_id
  ),
  abnormal_map AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      COUNT(*) AS map_abnormal_count
    FROM chartevents_map
    WHERE map_value < 65
    GROUP BY subject_id, hadm_id, stay_id
  ),
  abnormal_rr AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      COUNT(*) AS rr_abnormal_count
    FROM chartevents_rr
    WHERE rr_value > 20
    GROUP BY subject_id, hadm_id, stay_id
  ),
  instability_per_stay AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id,
      COALESCE(hr.hr_abnormal_count, 0) + 
      COALESCE(map.map_abnormal_count, 0) + 
      COALESCE(rr.rr_abnormal_count, 0) AS instability_index
    FROM icu_stays i
    LEFT JOIN abnormal_hr hr 
      ON i.subject_id = hr.subject_id AND i.hadm_id = hr.hadm_id AND i.stay_id = hr.stay_id
    LEFT JOIN abnormal_map map 
      ON i.subject_id = map.subject_id AND i.hadm_id = map.hadm_id AND i.stay_id = map.stay_id
    LEFT JOIN abnormal_rr rr 
      ON i.subject_id = rr.subject_id AND i.hadm_id = rr.hadm_id AND i.stay_id = rr.stay_id
  ),
  percentile_90 AS (
    SELECT 
      APPROX_QUANTILES(instability_index, 100)[OFFSET(90)] AS p90
    FROM instability_per_stay
  ),
  top_decile_ugib AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id,
      i.intime,
      i.los AS icu_los,
      a.hospital_expire_flag AS mortality,
      -- Binary indicators for abnormalities in first 48h
      (SELECT COUNT(*) > 0 FROM chartevents_hr hr 
        WHERE hr.subject_id = i.subject_id AND hr.hadm_id = i.hadm_id AND hr.stay_id = i.stay_id) AS tachycardia,
      (SELECT COUNT(*) > 0 FROM chartevents_map map 
        WHERE map.subject_id = i.subject_id AND map.hadm_id = i.hadm_id AND map.stay_id = i.stay_id AND map_value < 65) AS hypotension,
      (SELECT COUNT(*) > 0 FROM chartevents_rr rr 
        WHERE rr.subject_id = i.subject_id AND rr.hadm_id = i.hadm_id AND rr.stay_id = i.stay_id AND rr_value > 20) AS tachypnea
    FROM icu_stays i
    JOIN instability_per_stay inst 
      ON i.subject_id = inst.subject_id AND i.hadm_id = inst.hadm_id AND i.stay_id = inst.stay_id
    JOIN patients_admissions pa 
      ON i.subject_id = pa.subject_id AND i.hadm_id = pa.hadm_id
    JOIN percentile_90 p90 
      ON TRUE
    WHERE inst.instability_index >= p90.p90
  ),
  control_patients_admissions AS (
    SELECT 
      p.subject_id, 
      a.hadm_id, 
      a.admittime,
      a.hospital_expire_flag,
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age,
      p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
      AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 60 AND 70
      AND NOT EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.subject_id = p.subject_id 
          AND d.hadm_id = a.hadm_id
          AND d.icd_code IN ('K25.0', 'K25.1', 'K25.8', 'K25.9')
      )
  ),
  control_icu_stays AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.stay_id, 
      i.intime,
      i.los AS icu_los,
      a.hospital_expire_flag AS mortality
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN control_patients_admissions ca 
      ON i.subject_id = ca.subject_id AND i.hadm_id = ca.hadm_id
  ),
  control_chartevents_hr AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS hr_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN control_icu_stays i 
      ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
    WHERE ce.itemid = 211 
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  ),
  control_chartevents_map AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS map_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN control_icu_stays i 
      ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
    WHERE ce.itemid = 456 
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  ),
  control_chartevents_rr AS (
    SELECT 
      ce.subject_id, 
      ce.hadm_id, 
      ce.stay_id,
      ce.charttime,
      ce.valuenum AS rr_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN control_icu_stays i 
      ON ce.subject_id = i.subject_id AND ce.hadm_id = i.hadm_id AND ce.stay_id = i.stay_id
    WHERE ce.itemid = 220 
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  ),
  control_metrics AS (
    SELECT 
      c.subject_id, 
      c.hadm_id, 
      c.stay_id,
      c.icu_los,
      c.mortality,
      (SELECT COUNT(*) > 0 FROM control_chartevents_hr hr 
        WHERE hr.subject_id = c.subject_id AND hr.hadm_id = c.hadm_id AND hr.stay_id = c.stay_id AND hr_value > 100) AS tachycardia,
      (SELECT COUNT(*) > 0 FROM control_chartevents_map map 
        WHERE map.subject_id = c.subject_id AND map.hadm_id = c.hadm_id AND map.stay_id = c.stay_id AND map_value < 65) AS hypotension,
      (SELECT COUNT(*) > 0 FROM control_chartevents_rr rr 
        WHERE rr.subject_id = c.subject_id AND rr.hadm_id = c.hadm_id AND rr.stay_id = c.stay_id AND rr_value > 20) AS tachypnea
    FROM control_icu_stays c
  ),
  top_decile_agg AS (
    SELECT 
      'Top Decile UGIB' AS group_name,
      AVG(tachycardia) AS tachycardia_prop,
      AVG(hypotension) AS hypotension_prop,
      AVG(tachypnea) AS tachypnea_prop,
      AVG(icu_los) AS icu_los_avg,
      AVG(mortality) AS mortality_prop
    FROM top_decile_ugib
  ),
  control_agg AS (
    SELECT 
      'Control' AS group_name,
      AVG(tachycardia) AS tachycardia_prop,
      AVG(hypotension) AS hypotension_prop,
      AVG(tachypnea) AS tachypnea_prop,
      AVG(icu_los) AS icu_los_avg,
      AVG(mortality) AS mortality_prop
    FROM control_metrics
  )
SELECT * FROM top_decile_agg
UNION ALL
SELECT * FROM control_agg;