WITH gcs_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'GCS Total'
),
first_gcs AS (
  SELECT
    ce.stay_id,
    ce.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  CROSS JOIN gcs_item
  WHERE ce.itemid = gcs_item.itemid
    AND ce.valuenum IS NOT NULL
)
SELECT
  AVG(fg.valuenum) AS avg_first_gcs_total
FROM first_gcs fg
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON fg.stay_id = i.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
WHERE fg.rn = 1
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87;