WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 46 AND 56
)
SELECT 
  APPROX_QUANTILES(ce.valuenum, 2)[OFFSET(1)] AS median_temp_f
FROM cohort
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  ON cohort.stay_id = ce.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON ce.itemid = di.itemid
WHERE di.linksto = 'chartevents'
  AND LOWER(di.category) LIKE '%temperature%'
  AND di.unitname = '°F'
  AND ce.valuenum IS NOT NULL
  AND ce.charttime >= cohort.intime
  AND ce.charttime < cohort.intime + INTERVAL 24 HOUR;