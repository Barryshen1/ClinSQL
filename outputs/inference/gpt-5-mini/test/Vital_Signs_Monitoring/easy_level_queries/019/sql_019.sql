WITH map_itemids AS (
  -- find itemids that represent Mean Arterial Pressure (MAP)
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial%'
     OR LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%map%'
     OR LOWER(abbreviation) LIKE '%map%'
),
cohort_stays AS (
  -- ICU stays for female patients aged 73-83 that were in a step-down / IMC unit
  SELECT s.subject_id,
         s.hadm_id,
         s.stay_id,
         s.intime,
         s.outtime,
         s.first_careunit,
         s.last_careunit,
         p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    -- permissive match for step-down / intermediate care; adjust patterns if needed
    AND (
         LOWER(s.first_careunit) LIKE '%imc%' OR LOWER(s.last_careunit) LIKE '%imc%'
      OR LOWER(s.first_careunit) LIKE '%step%' OR LOWER(s.last_careunit) LIKE '%step%'
    )
),
per_stay_map AS (
  -- compute mean MAP per stay (only stays with at least one MAP measurement)
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    AVG(ce.valuenum) AS mean_map_stay,
    COUNT(ce.valuenum) AS n_map_measurements
  FROM cohort_stays cs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = cs.stay_id
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
    -- ensure charttime falls within the ICU stay window
    AND ce.charttime BETWEEN cs.intime AND cs.outtime
  GROUP BY cs.subject_id, cs.hadm_id, cs.stay_id
  HAVING COUNT(ce.valuenum) > 0
)
-- final aggregation: average of per-stay mean MAPs, and number of stays
SELECT
  ROUND(AVG(mean_map_stay), 2) AS avg_of_mean_map_per_stay_mm_hg,
  COUNT(*) AS n_stays_in_cohort
FROM per_stay_map;