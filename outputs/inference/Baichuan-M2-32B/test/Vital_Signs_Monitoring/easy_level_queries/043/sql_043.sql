WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),
gcs_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%GCS Total%'
    AND category = 'Neurological'
),
first_gcs_per_stay AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ce.valuenum AS first_gcs,
    ROW_NUMBER() OVER (PARTITION BY ie.stay_id ORDER BY ce.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN eligible_patients ep ON ie.subject_id = ep.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.subject_id = ce.subject_id
    AND ie.hadm_id = ce.hadm_id
    AND ie.stay_id = ce.stay_id
    AND ce.charttime BETWEEN ie.intime AND ie.outtime
  JOIN gcs_itemids gi ON ce.itemid = gi.itemid
  WHERE ce.valuenum IS NOT NULL
)
SELECT AVG(first_gcs) AS avg_first_gcs
FROM first_gcs_per_stay
WHERE rn = 1;