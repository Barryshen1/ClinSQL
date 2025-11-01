WITH ugi_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON d.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON d.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND (
      di.icd_code LIKE 'K25%' OR
      di.icd_code LIKE 'K26%' OR
      di.icd_code LIKE 'K27%' OR
      di.icd_code LIKE 'K28%' OR
      di.icd_code LIKE 'K22.0' OR
      di.icd_code LIKE 'K22.1' OR
      di.icd_code LIKE 'K22.2' OR
      di.icd_code LIKE 'K92.0' OR
      di.icd_code LIKE 'K92.1' OR
      di.icd_code LIKE 'K92.2'
    )
),

vital_index_calc AS (
  SELECT
    ugi.stay_id,
    SUM(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(CASE WHEN c.itemid = 220052 AND c.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN c.itemid = 220210 AND c.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea_count,
    (SUM(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) +
     SUM(CASE WHEN c.itemid = 220052 AND c.valuenum < 65 THEN 1 ELSE 0 END) +
     SUM(CASE WHEN c.itemid = 220210 AND c.valuenum > 20 THEN 1 ELSE 0 END)) AS vital_index
  FROM ugi_patients ugi
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON ugi.stay_id = c.stay_id
    AND c.charttime >= ugi.intime 
    AND c.charttime <= ugi.intime + INTERVAL '48' HOUR
  GROUP BY ugi.stay_id
),

percentile_95 AS (
  SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY vital_index) AS percentile_95
  FROM vital_index_calc
),

percentile_90 AS (
  SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY vital_index) AS p90
  FROM vital_index_calc
),

top_decile_ugi AS (
  SELECT
    ugi.stay_id,
    ugi.intime,
    ugi.hospital_expire_flag,
    i.los
  FROM ugi_patients ugi
  JOIN vital_index_calc vic ON ugi.stay_id = vic.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ugi.stay_id = i.stay_id
  WHERE vic.vital_index >= (SELECT p90 FROM percentile_90)
),

controls AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = p.subject_id
        AND (
          di.icd_code LIKE 'K25%' OR
          di.icd_code LIKE 'K26%' OR
          di.icd_code LIKE 'K27%' OR
          di.icd_code LIKE 'K28%' OR
          di.icd_code LIKE 'K22.0' OR
          di.icd_code LIKE 'K22.1' OR
          di.icd_code LIKE 'K22.2' OR
          di.icd_code LIKE 'K92.0' OR
          di.icd_code LIKE 'K92.1' OR
          di.icd_code LIKE 'K92.2'
        )
    )
),

top_decile_metrics AS (
  SELECT
    tdu.stay_id,
    MAX(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) AS has_tachycardia,
    MAX(CASE WHEN c.itemid = 220052 AND c.valuenum < 65 THEN 1 ELSE 0 END) AS has_hypotension,
    MAX(CASE WHEN c.itemid = 220210 AND c.valuenum > 20 THEN 1 ELSE 0 END) AS has_tachypnea,
    tdu.los,
    tdu.hospital_expire_flag
  FROM top_decile_ugi tdu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON tdu.stay_id = c.stay_id
    AND c.charttime >= tdu.intime 
    AND c.charttime <= tdu.intime + INTERVAL '48' HOUR
  GROUP BY tdu.stay_id, tdu.los, tdu.hospital_expire_flag
),

control_metrics AS (
  SELECT
    c.stay_id,
    MAX(CASE WHEN c2.itemid = 220045 AND c2.valuenum > 100 THEN 1 ELSE 0 END) AS has_tachycardia,
    MAX(CASE WHEN c2.itemid = 220052 AND c2.valuenum < 65 THEN 1 ELSE 0 END) AS has_hypotension,
    MAX(CASE WHEN c2.itemid = 220210 AND c2.valuenum > 20 THEN 1 ELSE 0 END) AS has_tachypnea,
    c.los,
    c.hospital_expire_flag
  FROM controls c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c2 
    ON c.stay_id = c2.stay_id
    AND c2.charttime >= c.intime 
    AND c2.charttime <= c.intime + INTERVAL '48' HOUR
  GROUP BY c.stay_id, c.los, c.hospital_expire_flag
)

SELECT '95th_percentile' AS metric, percentile_95 AS value FROM percentile_95
UNION ALL
SELECT 'top_decile_tachycardia', AVG(has_tachycardia) FROM top_decile_metrics
UNION ALL
SELECT 'top_decile_map', AVG(has_hypotension) FROM top_decile_metrics
UNION ALL
SELECT 'top_decile_tachypnea', AVG(has_tachypnea) FROM top_decile_metrics
UNION ALL
SELECT 'top_decile_los', AVG(los) FROM top_decile_metrics
UNION ALL
SELECT 'top_decile_mortality', AVG(hospital_expire_flag) FROM top_decile_metrics
UNION ALL
SELECT 'control_tachycardia', AVG(has_tachycardia) FROM control_metrics
UNION ALL
SELECT 'control_map', AVG(has_hypotension) FROM control_metrics
UNION ALL
SELECT 'control_tachypnea', AVG(has_tachypnea) FROM control_metrics
UNION ALL
SELECT 'control_los', AVG(los) FROM control_metrics
UNION ALL
SELECT 'control_mortality', AVG(hospital_expire_flag) FROM control_metrics;