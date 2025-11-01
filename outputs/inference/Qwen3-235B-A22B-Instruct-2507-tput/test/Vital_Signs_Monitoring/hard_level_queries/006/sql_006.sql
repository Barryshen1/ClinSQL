WITH ugib_codes AS (
  SELECT 'K92.0' AS icd_code, 10 AS icd_version
  UNION ALL SELECT 'K92.1', 10
  UNION ALL SELECT 'K92.2', 10
  UNION ALL SELECT '578.0', 9
  UNION ALL SELECT '578.1', 9
  UNION ALL SELECT '578.9', 9
),
ugib_diagnoses AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN ugib_codes u
    ON di.icd_code = u.icd_code AND di.icd_version = u.icd_version
),
patients_cohort AS (
  SELECT p.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN ugib_diagnoses u
    ON i.hadm_id = u.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) BETWEEN 60 AND 70
),
vital_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label IN ('Heart Rate', 'Mean Blood Pressure', 'Respiratory Rate')
),
vitals_first_48h AS (
  SELECT cv.subject_id, cv.stay_id,
    MAX(CASE WHEN di.label = 'Heart Rate' AND cv.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia,
    MAX(CASE WHEN di.label = 'Mean Blood Pressure' AND cv.valuenum < 65 THEN 1 ELSE 0 END) AS map_low,
    MAX(CASE WHEN di.label = 'Respiratory Rate' AND cv.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` cv
  INNER JOIN vital_items di
    ON cv.itemid = di.itemid
  INNER JOIN patients_cohort pc
    ON cv.stay_id = pc.stay_id
  WHERE cv.charttime >= pc.intime
    AND cv.charttime <= DATETIME_ADD(pc.intime, INTERVAL 48 HOUR)
    AND cv.valuenum IS NOT NULL
  GROUP BY cv.subject_id, cv.stay_id
),
vii_score AS (
  SELECT subject_id, stay_id,
    (tachycardia + map_low + tachypnea) AS vii,
    tachycardia, map_low, tachypnea
  FROM vitals_first_48h
),
vii_stats AS (
  SELECT *,
    PERCENTILE_CONT(vii, 0.95) OVER() AS vii_95th,
    PERCENT_RANK() OVER (ORDER BY vii) AS vii_percent_rank
  FROM vii_score
),
vii_groups AS (
  SELECT *,
    CASE WHEN vii_percent_rank >= 0.9 THEN 1 ELSE 0 END AS top_decile
  FROM vii_stats
),
outcomes AS (
  SELECT 
    vg.top_decile,
    AVG(CAST(vg.tachycardia AS FLOAT64)) AS pct_tachycardia,
    AVG(CAST(vg.map_low AS FLOAT64)) AS pct_map_low,
    AVG(CAST(vg.tachypnea AS FLOAT64)) AS pct_tachypnea,
    AVG(i.los) AS avg_los,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality
  FROM vii_groups vg
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON vg.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  GROUP BY vg.top_decile
)
SELECT 
  top_decile,
  MAX(vii_95th) AS vii_95th_percentile,
  pct_tachycardia,
  pct_map_low,
  pct_tachypnea,
  avg_los,
  mortality
FROM outcomes
CROSS JOIN vii_stats
GROUP BY top_decile, pct_tachycardia, pct_map_low, pct_tachypnea, avg_los, mortality
ORDER BY top_decile DESC;