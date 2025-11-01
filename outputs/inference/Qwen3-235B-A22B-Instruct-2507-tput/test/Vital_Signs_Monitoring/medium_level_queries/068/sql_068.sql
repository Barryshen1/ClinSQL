WITH map_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%map%'
    AND LOWER(category) LIKE '%vital signs%'
),
cohort AS (
  SELECT DISTINCT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS map_value,
    FLOOR(p.anchor_age + (EXTRACT(YEAR FROM ce.charttime) - p.anchor_year)) AS age_at_charttime,
    CASE
      WHEN ce.valuenum < 65 THEN '<65'
      WHEN ce.valuenum >= 65 AND ce.valuenum <= 74 THEN '65-74'
      WHEN ce.valuenum >= 75 AND ce.valuenum <= 84 THEN '75-84'
      WHEN ce.valuenum >= 85 THEN '>=85'
      ELSE NULL
    END AS map_category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_item mi ON ce.itemid = mi.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s ON ce.stay_id = s.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= s.intime AND ce.charttime <= s.outtime
),
cohort_filtered AS (
  SELECT *
  FROM cohort
  WHERE age_at_charttime BETWEEN 41 AND 51
    AND map_category IS NOT NULL
),
stroke_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND (
      d.icd_code LIKE 'I63%' OR
      d.icd_code = 'I64'
    )
),
patient_stroke_status AS (
  SELECT
    cf.subject_id,
    cf.map_category,
    MAX(CASE WHEN sd.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS had_stroke
  FROM cohort_filtered cf
  LEFT JOIN stroke_diagnoses sd ON cf.hadm_id = sd.hadm_id
  GROUP BY cf.subject_id, cf.map_category
),
summary AS (
  SELECT
    map_category,
    COUNT(*) AS patient_count,
    AVG(had_stroke) AS stroke_rate
  FROM patient_stroke_status
  GROUP BY map_category
  ORDER BY
    CASE map_category
      WHEN '<65' THEN 1
      WHEN '65-74' THEN 2
      WHEN '75-84' THEN 3
      WHEN '>=85' THEN 4
    END
)
SELECT
  map_category,
  patient_count,
  stroke_rate
FROM summary;