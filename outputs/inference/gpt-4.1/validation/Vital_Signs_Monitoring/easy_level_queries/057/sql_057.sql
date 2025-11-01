WITH resp_rate_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'respiratory rate'
),
male_35_45_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 35 AND 45
),
max_resp_rate_per_stay AS (
  SELECT
    icu.stay_id,
    MAX(ce.valuenum) AS max_resprate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN male_35_45_patients p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
  JOIN resp_rate_items ri
    ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
)
SELECT
  MIN(max_resprate) AS min_of_max_resprate
FROM max_resp_rate_per_stay;