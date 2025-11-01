WITH hfnc_stays AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pat.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
   AND icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 88 AND 98
    AND di.label LIKE '%High flow nasal cannula%'
),
gcs_values AS (
  SELECT ce.valuenum
  FROM hfnc_stays hs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON hs.subject_id = ce.subject_id
   AND hs.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Glasgow Coma Scale Total'
    AND ce.valuenum IS NOT NULL
    AND DATETIME_DIFF(ce.charttime, hs.intime, DAY) + 1 >= 2
)
SELECT
  COUNT(*) AS num_gcs_values,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_gcs
FROM gcs_values;