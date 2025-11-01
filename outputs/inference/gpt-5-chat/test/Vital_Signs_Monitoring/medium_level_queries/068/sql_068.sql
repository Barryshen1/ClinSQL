WITH female_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 41 AND 51
),
map_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE linksto = 'chartevents'
    AND (
      LOWER(label) LIKE '%mean arterial pressure%'
      OR LOWER(abbreviation) = 'map'
    )
),
stroke_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    CASE
      WHEN LOWER(dd.long_title) LIKE '%stroke%' THEN 1
      ELSE 0
    END AS stroke_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
),
stroke_per_adm AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(stroke_flag) AS stroke_flag
  FROM stroke_flags
  GROUP BY subject_id, hadm_id
),
map_measurements AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    ce.valuenum,
    CASE
      WHEN ce.valuenum < 65 THEN '<65'
      WHEN ce.valuenum >= 65 AND ce.valuenum <= 74 THEN '65-74'
      WHEN ce.valuenum >= 75 AND ce.valuenum <= 84 THEN '75-84'
      WHEN ce.valuenum >= 85 THEN '≥85'
    END AS map_category
  FROM female_icu f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON f.subject_id = ce.subject_id
   AND f.stay_id = ce.stay_id
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valueuom = 'mmHg'
),
map_with_stroke AS (
  SELECT
    m.subject_id,
    m.map_category,
    sa.stroke_flag
  FROM map_measurements m
  LEFT JOIN stroke_per_adm sa
    ON m.subject_id = sa.subject_id
   AND m.hadm_id = sa.hadm_id
)
SELECT
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN stroke_flag = 1 THEN subject_id END) AS stroke_patient_count,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN stroke_flag = 1 THEN subject_id END),
    COUNT(DISTINCT subject_id)
  ) * 100 AS stroke_rate_percent
FROM map_with_stroke
GROUP BY map_category
ORDER BY map_category;