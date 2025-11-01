WITH female_admissions AS (
  SELECT DISTINCT p.subject_id, i.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 82 AND 92
),
map_per_hadm AS (
  SELECT fa.hadm_id,
         MAX(ce.valuenum) AS max_map
  FROM female_admissions fa
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = fa.subject_id
   AND ce.hadm_id = fa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%mean arterial pressure%'
    AND ce.valuenum IS NOT NULL
  GROUP BY fa.hadm_id
)
SELECT
  QUAL[OFFSET(50)] AS median_of_max_map
FROM (
  SELECT APPROX_QUANTILES(max_map, 100) AS QUAL
  FROM map_per_hadm
);