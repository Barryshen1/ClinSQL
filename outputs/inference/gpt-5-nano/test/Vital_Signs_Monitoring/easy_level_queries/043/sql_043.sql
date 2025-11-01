WITH gcs_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%glasgow%' AND LOWER(label) LIKE '%total%'
),
gcs_events AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN gcs_items gi ON ce.itemid = gi.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  WHERE ce.charttime >= icu.intime
    AND ce.charttime <= icu.outtime
),
first_gcs AS (
  SELECT *
  FROM (
    SELECT
      subject_id, hadm_id, stay_id, charttime, valuenum,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id, stay_id ORDER BY charttime ASC) AS rn
    FROM gcs_events
  )
  WHERE rn = 1
),
aged_male AS (
  SELECT fg.subject_id, fg.hadm_id, fg.stay_id, fg.charttime, fg.valuenum
  FROM first_gcs AS fg
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON fg.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 77 AND 87
)
SELECT AVG(valuenum) AS avg_first_gcs_total_at_icu_admission
FROM aged_male
WHERE valuenum IS NOT NULL;