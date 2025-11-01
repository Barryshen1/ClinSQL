WITH patient_icu_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 66 AND 76
),
ventilated_stays AS (
  SELECT DISTINCT
    stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents
  WHERE itemid = 225468  -- Invasive ventilation
),
sbp_measurements AS (
  SELECT
    ce.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN patient_icu_age pia
    ON ce.stay_id = pia.stay_id
  INNER JOIN ventilated_stays vs
    ON pia.stay_id = vs.stay_id
  WHERE ce.itemid IN (220050, 220179, 224167, 225309, 225310)  -- SBP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= pia.intime
    AND ce.charttime <= pia.intime + INTERVAL '6' HOUR
)
SELECT
  PERCENTILE_CONT(sbp, 0.75) OVER() - PERCENTILE_CONT(sbp, 0.25) OVER() AS iqr_sbp
FROM sbp_measurements
LIMIT 1;