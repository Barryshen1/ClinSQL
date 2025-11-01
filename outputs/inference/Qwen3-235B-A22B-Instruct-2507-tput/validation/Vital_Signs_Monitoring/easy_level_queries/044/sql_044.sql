WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 82 AND 92
),
stay_max_map AS (
  SELECT
    ce.hadm_id,
    MAX(ce.valuenum) AS max_map
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN filtered_patients fp
    ON icu.subject_id = fp.subject_id
  WHERE LOWER(di.label) LIKE '%arterial pressure mean%'
    OR LOWER(di.label) = 'mean blood pressure'
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.hadm_id
)
SELECT
  APPROX_QUANTILES(max_map, 100)[OFFSET(50)] AS median_max_map
FROM stay_max_map
WHERE max_map IS NOT NULL;