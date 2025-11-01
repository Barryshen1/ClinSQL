WITH
-- Identify admissions with a diagnosis containing 'respiratory failure'
arf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%respiratory failure%'
),

-- Basic icu stays with patient & admission info
stays AS (
  SELECT s.*,
         p.gender,
         p.anchor_age,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
),

-- Aggregate MAP and HR counts in the first 72 hours for each stay
ce_counts AS (
  SELECT
    s.stay_id,
    SUM(CASE WHEN (LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%')
             THEN 1 ELSE 0 END) AS map_total,
    SUM(CASE WHEN (LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%')
             AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low,
    SUM(CASE WHEN (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%' OR LOWER(di.label) LIKE '%pulse%')
             THEN 1 ELSE 0 END) AS hr_total,
    SUM(CASE WHEN (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%' OR LOWER(di.label) LIKE '%pulse%')
             AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = s.stay_id
       AND ce.valuenum IS NOT NULL
       AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  GROUP BY s.stay_id
),

-- Combine stays with their measurement aggregates and patient/admission info
per_stay AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime,
    s.los,
    s.gender,
    s.anchor_age,
    s.hospital_expire_flag,
    c.map_total,
    c.map_low,
    c.hr_total,
    c.hr_high,
    -- compute burdens; NULL if denominator = 0 or null
    CASE WHEN c.map_total > 0 THEN SAFE_DIVIDE(c.map_low, c.map_total) ELSE NULL END AS map_burden,
    CASE WHEN c.hr_total > 0 THEN SAFE_DIVIDE(c.hr_high, c.hr_total) ELSE NULL END AS hr_burden,
    -- composite only where both burdens non-null (i.e., at least one measurement for each)
    CASE
      WHEN c.map_total > 0 AND c.hr_total > 0
      THEN SAFE_DIVIDE(c.map_low, c.map_total) + SAFE_DIVIDE(c.hr_high, c.hr_total)
      ELSE NULL
    END AS composite_instability
  FROM stays s
  LEFT JOIN ce_counts c
    ON s.stay_id = c.stay_id
),

-- Cohort: male, age 82-92, had respiratory failure on the admission
cohort_stays AS (
  SELECT ps.*
  FROM per_stay ps
  WHERE ps.gender = 'M'
    AND ps.anchor_age BETWEEN 82 AND 92
    AND ps.hadm_id IN (SELECT hadm_id FROM arf_hadm)
    -- require composite to be computable (both MAP and HR measured in first 72h)
    AND ps.composite_instability IS NOT NULL
),

-- General ICU stays: all stays with computable composite
general_stays AS (
  SELECT ps.*
  FROM per_stay ps
  WHERE ps.composite_instability IS NOT NULL
)

-- Final aggregation: compute quartiles (p25/p50/p75), IQR, mean burdens, mean LOS, mortality rate
SELECT
  grp,
  COUNT(*) AS n_stays,
  -- approximate percentiles of composite instability using APPROX_QUANTILES
  APPROX_QUANTILES(composite_instability, 100)[OFFSET(25)] AS composite_p25,
  APPROX_QUANTILES(composite_instability, 100)[OFFSET(50)] AS composite_median,
  APPROX_QUANTILES(composite_instability, 100)[OFFSET(75)] AS composite_p75,
  -- IQR
  (APPROX_QUANTILES(composite_instability, 100)[OFFSET(75)]
   - APPROX_QUANTILES(composite_instability, 100)[OFFSET(25)]) AS composite_IQR,
  -- average burdens and LOS
  AVG(map_burden) AS mean_map_burden,
  AVG(hr_burden) AS mean_hr_burden,
  AVG(composite_instability) AS mean_composite_instability,
  AVG(los) AS mean_icu_los_days,
  -- mortality rate (hospital_expire_flag assumed 0/1)
  AVG(COALESCE(hospital_expire_flag, 0)) AS hospital_mortality_rate
FROM (
  SELECT 'Cohort: male age 82-92 with respiratory failure' AS grp, * FROM cohort_stays
  UNION ALL
  SELECT 'General ICU (all stays with MAP & HR in first 72h)' AS grp, * FROM general_stays
)
GROUP BY grp
ORDER BY grp;