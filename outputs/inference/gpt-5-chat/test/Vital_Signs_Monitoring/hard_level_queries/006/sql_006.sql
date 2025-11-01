WITH ugib_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, i.stay_id, p.anchor_age, p.gender,
         a.hospital_expire_flag, i.los, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.anchor_age BETWEEN 60 AND 70
    AND p.gender = 'M'
    AND (LOWER(dd.long_title) LIKE '%upper%gastro%hemorrhage%'
         OR LOWER(dd.long_title) LIKE '%upper%gi%bleed%'
         OR LOWER(dd.long_title) LIKE '%esophageal varices with bleeding%'
         OR LOWER(dd.long_title) LIKE '%duodenal%hemorrhage%'
         OR LOWER(dd.long_title) LIKE '%gastric%hemorrhage%')
),
vitals_itemids AS (
  SELECT
    MAX(IF(LOWER(label) LIKE '%heart rate%', itemid, NULL)) AS hr_itemid,
    MAX(IF(LOWER(label) LIKE '%resp%rate%', itemid, NULL)) AS rr_itemid,
    MAX(IF(LOWER(label) LIKE '%mean%art%pressure%', itemid, NULL)) AS map_itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
),
vitals AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id,
         CASE WHEN ce.itemid = vi.hr_itemid AND ce.valuenum > 100 THEN 1 ELSE 0 END AS tachycardia,
         CASE WHEN ce.itemid = vi.map_itemid AND ce.valuenum < 65 THEN 1 ELSE 0 END AS low_map,
         CASE WHEN ce.itemid = vi.rr_itemid AND ce.valuenum > 20 THEN 1 ELSE 0 END AS tachypnea
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  CROSS JOIN vitals_itemids vi
  JOIN ugib_patients u
    ON ce.subject_id = u.subject_id AND ce.hadm_id = u.hadm_id AND ce.stay_id = u.stay_id
  WHERE ce.charttime BETWEEN u.intime AND DATETIME_ADD(u.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),
index_per_stay AS (
  SELECT stay_id,
         SUM(tachycardia) + SUM(low_map) + SUM(tachypnea) AS instability_index,
         MAX(IF(tachycardia=1,1,0)) AS any_tachycardia,
         MAX(IF(low_map=1,1,0)) AS any_low_map,
         MAX(IF(tachypnea=1,1,0)) AS any_tachypnea
  FROM vitals
  GROUP BY stay_id
),
ugib_index AS (
  SELECT u.*, idx.instability_index, idx.any_tachycardia, idx.any_low_map, idx.any_tachypnea
  FROM ugib_patients u
  JOIN index_per_stay idx
    ON u.stay_id = idx.stay_id
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_index, 100)[SAFE_OFFSET(95)] AS p95,
    APPROX_QUANTILES(instability_index, 10)[SAFE_OFFSET(9)] AS p90
  FROM ugib_index
),
controls AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, i.stay_id, p.anchor_age, p.gender,
         a.hospital_expire_flag, i.los, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.anchor_age BETWEEN 60 AND 70
    AND p.gender = 'M'
    AND NOT (
         LOWER(dd.long_title) LIKE '%upper%gastro%hemorrhage%'
         OR LOWER(dd.long_title) LIKE '%upper%gi%bleed%'
         OR LOWER(dd.long_title) LIKE '%esophageal varices with bleeding%'
         OR LOWER(dd.long_title) LIKE '%duodenal%hemorrhage%'
         OR LOWER(dd.long_title) LIKE '%gastric%hemorrhage%'
    )
),
control_vitals AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id,
         CASE WHEN ce.itemid = vi.hr_itemid AND ce.valuenum > 100 THEN 1 ELSE 0 END AS tachycardia,
         CASE WHEN ce.itemid = vi.map_itemid AND ce.valuenum < 65 THEN 1 ELSE 0 END AS low_map,
         CASE WHEN ce.itemid = vi.rr_itemid AND ce.valuenum > 20 THEN 1 ELSE 0 END AS tachypnea
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  CROSS JOIN vitals_itemids vi
  JOIN controls c
    ON ce.subject_id = c.subject_id AND ce.hadm_id = c.hadm_id AND ce.stay_id = c.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),
control_index AS (
  SELECT stay_id,
         SUM(tachycardia) + SUM(low_map) + SUM(tachypnea) AS instability_index,
         MAX(IF(tachycardia=1,1,0)) AS any_tachycardia,
         MAX(IF(low_map=1,1,0)) AS any_low_map,
         MAX(IF(tachypnea=1,1,0)) AS any_tachypnea
  FROM control_vitals
  GROUP BY stay_id
),
control_index_join AS (
  SELECT c.*, idx.instability_index, idx.any_tachycardia, idx.any_low_map, idx.any_tachypnea
  FROM controls c
  JOIN control_index idx
    ON c.stay_id = idx.stay_id
)
SELECT
  p.p95 AS instability_index_95th_percentile,
  -- Comparison top decile UGIB vs controls
  SUM(CASE WHEN u.instability_index >= p.p90 THEN 1 ELSE 0 END) AS ugib_top_decile_n,
  AVG(CASE WHEN u.instability_index >= p.p90 THEN u.any_tachycardia ELSE NULL END) AS ugib_tachycardia_rate,
  AVG(CASE WHEN u.instability_index >= p.p90 THEN u.any_low_map ELSE NULL END) AS ugib_low_map_rate,
  AVG(CASE WHEN u.instability_index >= p.p90 THEN u.any_tachypnea ELSE NULL END) AS ugib_tachypnea_rate,
  AVG(CASE WHEN u.instability_index >= p.p90 THEN u.los ELSE NULL END) AS ugib_mean_icu_los,
  AVG(CASE WHEN u.instability_index >= p.p90 THEN u.hospital_expire_flag ELSE NULL END) AS ugib_mortality_rate,
  SUM(CASE WHEN c.instability_index >= p.p90 THEN 1 ELSE 0 END) AS control_top_decile_n,
  AVG(CASE WHEN c.instability_index >= p.p90 THEN c.any_tachycardia ELSE NULL END) AS control_tachycardia_rate,
  AVG(CASE WHEN c.instability_index >= p.p90 THEN c.any_low_map ELSE NULL END) AS control_low_map_rate,
  AVG(CASE WHEN c.instability_index >= p.p90 THEN c.any_tachypnea ELSE NULL END) AS control_tachypnea_rate,
  AVG(CASE WHEN c.instability_index >= p.p90 THEN c.los ELSE NULL END) AS control_mean_icu_los,
  AVG(CASE WHEN c.instability_index >= p.p90 THEN c.hospital_expire_flag ELSE NULL END) AS control_mortality_rate
FROM ugib_index u
CROSS JOIN percentiles p
JOIN control_index_join c
  ON u.anchor_age = c.anchor_age -- age-matched
GROUP BY p.p95;