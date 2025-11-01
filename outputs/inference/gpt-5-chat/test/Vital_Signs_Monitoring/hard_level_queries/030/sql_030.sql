WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    adm.hospital_expire_flag,
    ie.intime,
    ie.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.subject_id = adm.subject_id
   AND ie.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON ie.subject_id = dx.subject_id
   AND ie.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
   AND dx.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      (dx.icd_version = 9 AND dx.icd_code = '51881')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'J96%')
    )
),
vitals_48h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    SUM(CASE WHEN ce.itemid IN (220052, 220181) AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS low_map_events,
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS high_hr_events
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
   AND c.hadm_id = ce.hadm_id
   AND c.stay_id = ce.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (220052, 220181, 220045)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
vital_index AS (
  SELECT
    v.*,
    (low_map_events + high_hr_events) AS vital_instability_index
  FROM vitals_48h v
),
vital_percentiles AS (
  SELECT
    PERCENTILE_CONT(vital_instability_index, 0.95) OVER() AS p95_index,
    PERCENTILE_CONT(vital_instability_index, 0.75) OVER() AS p75_index
  FROM vital_index
  LIMIT 1
),
labeled AS (
  SELECT
    vi.*,
    c.hospital_expire_flag,
    DATETIME_DIFF(c.outtime, c.intime, HOUR)/24.0 AS icu_los_days,
    CASE WHEN vi.vital_instability_index >= vp.p75_index THEN 1 ELSE 0 END AS top_quartile
  FROM vital_index vi
  JOIN cohort c
    ON vi.subject_id = c.subject_id
   AND vi.stay_id = c.stay_id
  CROSS JOIN vital_percentiles vp
),
comparisons AS (
  SELECT
    'top_quartile' AS group_name,
    COUNT(*) AS n_stays,
    AVG(CASE WHEN low_map_events > 0 THEN 1 ELSE 0 END) AS prop_low_map,
    AVG(CASE WHEN high_hr_events > 0 THEN 1 ELSE 0 END) AS prop_high_hr,
    AVG(icu_los_days) AS mean_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM labeled
  WHERE top_quartile = 1
  UNION ALL
  SELECT
    'general_icu' AS group_name,
    COUNT(*) AS n_stays,
    AVG(CASE WHEN low_map_events > 0 THEN 1 ELSE 0 END) AS prop_low_map,
    AVG(CASE WHEN high_hr_events > 0 THEN 1 ELSE 0 END) AS prop_high_hr,
    AVG(icu_los_days) AS mean_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM labeled
)
SELECT
  (SELECT p95_index FROM vital_percentiles) AS p95_vital_instability_index,
  *
FROM comparisons;