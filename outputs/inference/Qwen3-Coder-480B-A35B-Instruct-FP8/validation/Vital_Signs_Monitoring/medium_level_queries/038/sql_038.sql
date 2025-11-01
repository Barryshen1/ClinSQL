WITH ventilated_icu_stays AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON icu.stay_id = proc.stay_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 66 AND 76
    AND proc.itemid = 225792 -- Invasive Ventilation
    AND proc.starttime BETWEEN icu.intime AND icu.outtime
),
sbp_measurements AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN ventilated_icu_stays vis
    ON ce.stay_id = vis.stay_id
  WHERE ce.itemid = 220050 -- Arterial BP systolic
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= vis.intime
    AND ce.charttime <= DATETIME_ADD(vis.intime, INTERVAL 6 HOUR)
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr
FROM sbp_measurements;