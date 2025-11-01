WITH map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
icu_subset AS (
  SELECT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 73 AND 83
    AND LOWER(ie.first_careunit) IN ('step-down', 'imc')
),
map_values_per_stay AS (
  SELECT ce.stay_id,
         AVG(ce.valuenum) AS avg_map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  JOIN icu_subset icu
    ON ce.stay_id = icu.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY ce.stay_id
)
SELECT AVG(avg_map) AS average_map_per_stay
FROM map_values_per_stay;