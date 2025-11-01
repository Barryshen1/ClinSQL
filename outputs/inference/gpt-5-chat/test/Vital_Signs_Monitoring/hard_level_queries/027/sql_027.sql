WITH rrt_patients AS (
  SELECT DISTINCT pe.subject_id, pe.hadm_id, pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  WHERE LOWER(pe.ordercategorydescription) LIKE '%dialysis%'
     OR LOWER(pe.ordercategorydescription) LIKE '%rrt%'
     OR LOWER(pe.ordercategorydescription) LIKE '%renal replacement%'
),
demo AS (
  SELECT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),
icu_info AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
vitals AS (
  SELECT c.subject_id, c.hadm_id, c.stay_id,
         TIMESTAMP_DIFF(c.charttime, i.intime, HOUR) AS hr_since_icu,
         CASE WHEN c.itemid IN (220052, 52) THEN c.valuenum END AS map_val,
         CASE WHEN c.itemid IN (220045, 211) THEN c.valuenum END AS hr_val
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_info i
    ON c.subject_id = i.subject_id
   AND c.stay_id = i.stay_id
  WHERE c.itemid IN (220052, 52, 220045, 211)
    AND c.valuenum IS NOT NULL
    AND TIMESTAMP_DIFF(c.charttime, i.intime, HOUR) BETWEEN 0 AND 72
),
hourly_avg AS (
  SELECT subject_id, hadm_id, stay_id, hr_since_icu,
         AVG(map_val) AS avg_map,
         AVG(hr_val) AS avg_hr
  FROM vitals
  GROUP BY subject_id, hadm_id, stay_id, hr_since_icu
),
instability_hours AS (
  SELECT subject_id, hadm_id, stay_id,
         SUM(CASE WHEN avg_map < 65 AND avg_hr > 100 THEN 1 ELSE 0 END) AS unstable_hours,
         COUNT(*) AS total_hours
  FROM hourly_avg
  GROUP BY subject_id, hadm_id, stay_id
),
vital_index AS (
  SELECT ih.subject_id, ih.hadm_id, ih.stay_id,
         ih.unstable_hours,
         ih.total_hours,
         SAFE_DIVIDE(ih.unstable_hours, ih.total_hours) AS vital_instability_index
  FROM instability_hours ih
),
cohort AS (
  SELECT vi.subject_id, vi.hadm_id, vi.stay_id,
         d.gender, d.anchor_age, i.los, d.hospital_expire_flag,
         vi.vital_instability_index, vi.unstable_hours
  FROM vital_index vi
  JOIN demo d ON vi.subject_id = d.subject_id AND vi.hadm_id = d.hadm_id
  JOIN icu_info i ON vi.subject_id = i.subject_id AND vi.stay_id = i.stay_id
  JOIN rrt_patients rp ON vi.subject_id = rp.subject_id AND vi.stay_id = rp.stay_id
)
SELECT
  CASE WHEN gender = 'F' AND anchor_age = 63 THEN '63yo_female'
       ELSE 'other_rrt'
  END AS subgroup,
  COUNT(*) AS n_patients,
  ROUND(APPROX_QUANTILES(vital_instability_index, 100)[SAFE_OFFSET(25)], 3) AS p25_vii,
  ROUND(APPROX_QUANTILES(vital_instability_index, 100)[SAFE_OFFSET(50)], 3) AS p50_vii,
  ROUND(APPROX_QUANTILES(vital_instability_index, 100)[SAFE_OFFSET(75)], 3) AS p75_vii,
  ROUND(APPROX_QUANTILES(vital_instability_index, 100)[SAFE_OFFSET(90)], 3) AS p90_vii,
  ROUND(APPROX_QUANTILES(unstable_hours, 100)[SAFE_OFFSET(25)], 1) AS p25_hours,
  ROUND(APPROX_QUANTILES(unstable_hours, 100)[SAFE_OFFSET(50)], 1) AS p50_hours,
  ROUND(APPROX_QUANTILES(unstable_hours, 100)[SAFE_OFFSET(75)], 1) AS p75_hours,
  ROUND(APPROX_QUANTILES(unstable_hours, 100)[SAFE_OFFSET(90)], 1) AS p90_hours,
  ROUND(APPROX_QUANTILES(los, 100)[SAFE_OFFSET(50)], 2) AS median_icu_los,
  ROUND(
    APPROX_QUANTILES(los, 100)[SAFE_OFFSET(75)] - APPROX_QUANTILES(los, 100)[SAFE_OFFSET(25)],
    2
  ) AS iqr_icu_los,
  SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate
FROM cohort
GROUP BY subgroup
ORDER BY subgroup;