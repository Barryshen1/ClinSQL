WITH
  patients_filtered AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 41 AND 51
  ),
  icu_stays AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      i.intime, 
      i.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN patients_filtered p ON i.subject_id = p.subject_id
  ),
  map_measurements AS (
    SELECT 
      m.subject_id,
      m.hadm_id,
      m.valuenum AS map_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` m
    JOIN icu_stays i ON m.subject_id = i.subject_id
      AND m.hadm_id = i.hadm_id
      AND m.charttime BETWEEN i.intime AND i.outtime
    WHERE m.itemid = 456  -- MAP itemid
      AND m.valuenum IS NOT NULL
      AND m.valuenum > 20 AND m.valuenum < 200  -- valid MAP range
  ),
  stroke_flags AS (
    SELECT 
      p.subject_id,
      MAX(CASE WHEN d.icd_code BETWEEN 'I60' AND 'I699' THEN 1 ELSE 0 END) AS has_stroke
    FROM patients_filtered p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON p.subject_id = d.subject_id
      AND d.icd_version = 10
    GROUP BY p.subject_id
  ),
  patient_map_categories AS (
    SELECT 
      mm.subject_id,
      mm.hadm_id,
      CASE 
        WHEN mm.map_value < 65 THEN '<65'
        WHEN mm.map_value BETWEEN 65 AND 74 THEN '65-74'
        WHEN mm.map_value BETWEEN 75 AND 84 THEN '75-84'
        WHEN mm.map_value >= 85 THEN '>=85'
      END AS map_category
    FROM map_measurements mm
  ),
  distinct_patients_per_category AS (
    SELECT 
      p.subject_id,
      p.map_category,
      s.has_stroke
    FROM patient_map_categories p
    JOIN stroke_flags s ON p.subject_id = s.subject_id
    GROUP BY p.subject_id, p.map_category, s.has_stroke
  )
SELECT 
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(100.0 * SUM(has_stroke) / COUNT(DISTINCT subject_id), 2) AS stroke_rate_percent
FROM distinct_patients_per_category
GROUP BY map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;