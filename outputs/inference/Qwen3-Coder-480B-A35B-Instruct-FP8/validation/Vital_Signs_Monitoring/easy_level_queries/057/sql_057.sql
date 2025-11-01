WITH rr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 35 AND 45
),
icu_stays_with_rr AS (
  SELECT
    icu.stay_id,
    MAX(ce.valuenum) AS max_rr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN filtered_patients pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  INNER JOIN rr_itemids ri
    ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
)
SELECT
  MIN(max_rr) AS min_of_max_rr
FROM icu_stays_with_rr;