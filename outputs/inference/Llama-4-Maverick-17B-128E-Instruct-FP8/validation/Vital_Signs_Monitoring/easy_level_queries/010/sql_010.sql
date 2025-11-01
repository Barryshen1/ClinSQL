WITH dbp_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Diastolic Blood Pressure%' OR abbreviation LIKE '%Dias BP%' OR label LIKE '%NBP Dias%'
),
patient_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 71 AND 81
),
max_dbp_per_stay AS (
  SELECT ie.stay_id, MAX(ce.valuenum) AS max_dbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  INNER JOIN patient_cohort p ON ie.subject_id = p.subject_id
  WHERE ce.itemid IN (SELECT itemid FROM dbp_itemid)
  GROUP BY ie.stay_id
)
SELECT APPROX_QUANTILES(max_dbp, 100)[OFFSET(50)] AS median_max_dbp
FROM max_dbp_per_stay;