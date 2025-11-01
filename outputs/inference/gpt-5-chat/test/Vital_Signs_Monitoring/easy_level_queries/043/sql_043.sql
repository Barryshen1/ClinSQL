WITH gcs_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%gcs total%'
)
, first_gcs_per_stay AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    MIN(ce.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN gcs_itemids gi
    ON ce.itemid = gi.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
)
, first_gcs_values AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    AVG(ce.valuenum) AS first_gcs_total
  FROM first_gcs_per_stay f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = f.subject_id
   AND ce.hadm_id = f.hadm_id
   AND ce.stay_id = f.stay_id
   AND ce.charttime = f.first_charttime
  JOIN gcs_itemids gi
    ON ce.itemid = gi.itemid
  GROUP BY f.subject_id, f.hadm_id, f.stay_id
)
SELECT
  AVG(first_gcs_total) AS avg_first_gcs_total
FROM first_gcs_values fg
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON fg.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87;