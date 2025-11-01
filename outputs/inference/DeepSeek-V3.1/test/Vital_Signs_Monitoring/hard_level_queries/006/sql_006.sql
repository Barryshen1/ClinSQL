WITH ugib_patients AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    i.stay_id,
    i.first_careunit,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    -- Calculate age at admission (fixed DATETIME function)
    DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    -- More specific UGIB-related ICD codes
    AND (dd.icd_code LIKE 'K92.0%'  -- Hematemesis
         OR dd.icd_code LIKE 'K92.1%'  -- Melaena
         OR dd.icd_code LIKE 'K92.2%'  -- Gastrointestinal hemorrhage, unspecified
         OR dd.icd_code LIKE 'K25.0%'  -- Acute gastric ulcer with hemorrhage
         OR dd.icd_code LIKE 'K26.0%'  -- Acute duodenal ulcer with hemorrhage
         OR dd.icd_code LIKE 'K27.0%'  -- Acute peptic ulcer with hemorrhage
         OR dd.icd_code LIKE 'K28.0%'  -- Acute gastrojejunal ulcer with hemorrhage
         OR dd.icd_code LIKE '530.21%' -- Ulcerative esophagitis with bleeding
         OR dd.icd_code LIKE '530.7%'  -- Gastroesophageal laceration-hemorrhage
         OR dd.icd_code LIKE '530.82%' -- Esophageal hemorrhage
         OR dd.icd_code LIKE '531.0%'  -- Acute gastric ulcer with hemorrhage
         OR dd.icd_code LIKE '532.0%'  -- Acute duodenal ulcer with hemorrhage
         OR dd.icd_code LIKE '533.0%'  -- Acute peptic ulcer with hemorrhage
         OR dd.icd_code LIKE '534.0%') -- Acute gastrojejunal ulcer with hemorrhage
    -- Age filter at admission between 60 and 70
    AND (DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 60 AND 70
  QUALIFY ROW_NUMBER() OVER(PARTITION BY i.stay_id ORDER BY i.intime) = 1  -- First ICU stay per admission
),
vitals AS (
  SELECT 
    v.subject_id,
    v.stay_id,
    v.charttime,
    MAX(CASE WHEN v.itemid = 220045 THEN v.valuenum END) AS heart_rate,
    MAX(CASE WHEN v.itemid = 220181 THEN v.valuenum END) AS map,
    MAX(CASE WHEN v.itemid = 220210 THEN v.valuenum END) AS resp_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` v
  INNER JOIN ugib_patients u
    ON v.stay_id = u.stay_id
  WHERE v.itemid IN (220045, 220181, 220210)
    AND v.charttime BETWEEN u.intime AND DATETIME_ADD(u.intime, INTERVAL 48 HOUR)
  GROUP BY v.subject_id, v.stay_id, v.charttime
  HAVING 
    MAX(CASE WHEN v.itemid = 220045 THEN v.valuenum END) IS NOT NULL
    AND MAX(CASE WHEN v.itemid = 220181 THEN v.valuenum END) IS NOT NULL
    AND MAX(CASE WHEN v.itemid = 220210 THEN v.valuenum END) IS NOT NULL
),
vital_instability AS (
  SELECT 
    subject_id,
    stay_id,
    MAX(
      CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END +
      CASE WHEN map < 65 THEN 1 ELSE 0 END +
      CASE WHEN resp_rate > 20 THEN 1 ELSE 0 END
    ) AS vii
  FROM vitals
  GROUP BY subject_id, stay_id
),
cohort_vii AS (
  SELECT 
    u.*,
    COALESCE(v.vii, 0) AS vii  -- If no vitals, assume stable (0)
  FROM ugib_patients u
  LEFT JOIN vital_instability v
    ON u.stay_id = v.stay_id
),
percentile_values AS (
  SELECT
    APPROX_QUANTILES(vii, 100) AS vii_percentiles
  FROM cohort_vii
),
p90_p95 AS (
  SELECT
    vii_percentiles[OFFSET(90)] AS p90_vii,
    vii_percentiles[OFFSET(95)] AS p95_vii
  FROM percentile_values
),
cohort_with_percentiles AS (
  SELECT 
    c.*,
    (SELECT p95_vii FROM p90_p95) AS p95_vii,
    (SELECT p90_vii FROM p90_p95) AS p90_vii
  FROM cohort_vii c
),
top_decile AS (
  SELECT 
    *,
    CASE WHEN vii >= (SELECT p90_vii FROM p90_p95) THEN 1 ELSE 0 END AS is_top_decile
  FROM cohort_with_percentiles
),
controls AS (
  SELECT 
    * 
  FROM top_decile 
  WHERE is_top_decile = 0
  ORDER BY RAND()
  LIMIT (SELECT COUNT(*) FROM top_decile WHERE is_top_decile = 1)
),
comparison_groups AS (
  SELECT 
    'Top Decile' AS group_label,
    td.subject_id,
    td.hadm_id,
    td.stay_id,
    td.vii,
    td.icu_los,
    td.hospital_expire_flag,
    -- Use the most abnormal values from the 48-hour period
    MAX(v.heart_rate) AS max_heart_rate,
    MIN(v.map) AS min_map,
    MAX(v.resp_rate) AS max_resp_rate
  FROM top_decile td
  INNER JOIN vitals v ON td.stay_id = v.stay_id
  WHERE td.is_top_decile = 1
  GROUP BY td.subject_id, td.hadm_id, td.stay_id, td.vii, td.icu_los, td.hospital_expire_flag

  UNION ALL

  SELECT 
    'Control' AS group_label,
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.vii,
    c.icu_los,
    c.hospital_expire_flag,
    MAX(v.heart_rate) AS max_heart_rate,
    MIN(v.map) AS min_map,
    MAX(v.resp_rate) AS max_resp_rate
  FROM controls c
  INNER JOIN vitals v ON c.stay_id = v.stay_id
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.vii, c.icu_los, c.hospital_expire_flag
)
SELECT 
  group_label,
  COUNT(DISTINCT subject_id) AS n_patients,
  AVG(vii) AS avg_vii,
  -- Prevalence of abnormalities using the most extreme values from the 48-hour period
  AVG(CASE WHEN max_heart_rate > 100 THEN 1.0 ELSE 0 END) AS tachycardia_prevalence,
  AVG(CASE WHEN min_map < 65 THEN 1.0 ELSE 0 END) AS hypotension_prevalence,
  AVG(CASE WHEN max_resp_rate > 20 THEN 1.0 ELSE 0 END) AS tachypnea_prevalence,
  -- ICU LOS and mortality
  AVG(icu_los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM comparison_groups
GROUP BY group_label;