WITH eligible_icustays AS (
  SELECT 
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime,
    patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients 
    ON icustays.subject_id = patients.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions 
    ON icustays.subject_id = admissions.subject_id 
    AND icustays.hadm_id = admissions.hadm_id
  WHERE 
    patients.gender = 'M'
    AND patients.anchor_age BETWEEN 66 AND 76
    AND EXTRACT(YEAR FROM admissions.admittime) = patients.anchor_year
),
ventilated_icustays AS (
  SELECT DISTINCT
    eis.subject_id,
    eis.hadm_id,
    eis.stay_id,
    eis.intime,
    eis.outtime,
    eis.age_at_icu
  FROM eligible_icustays eis
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    WHERE 
      ie.subject_id = eis.subject_id
      AND ie.hadm_id = eis.hadm_id
      AND ie.stay_id = eis.stay_id
      AND ie.itemid IN (
        SELECT itemid 
        FROM `physionet-data.mimiciv_3_1_icu.d_items` 
        WHERE (category = 'Medication' OR category = 'Procedure') 
          AND (label LIKE '%ventilator%' OR label LIKE '%mechanical ventilation%')
      )
      AND ie.starttime BETWEEN eis.intime AND eis.outtime
  )
),
sbp_measurements AS (
  SELECT 
    v.stay_id,
    ce.valuenum AS sbp_value
  FROM ventilated_icustays v
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON v.subject_id = ce.subject_id 
    AND v.hadm_id = ce.hadm_id 
    AND v.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (
      SELECT itemid 
      FROM `physionet-data.mimiciv_3_1_icu.d_items` 
      WHERE label LIKE '%systolic%' 
        AND (category = 'Vital Signs' OR category = 'Cardiovascular')
    )
    AND ce.charttime BETWEEN v.intime AND v.intime + INTERVAL 6 HOUR
    AND ce.valuenum IS NOT NULL
),
all_sbp AS (
  SELECT sbp_value
  FROM sbp_measurements
)
SELECT 
  APPROX_QUANTILES(sbp_value, 4)[SAFE_OFFSET(1)] AS q1,
  APPROX_QUANTILES(sbp_value, 4)[SAFE_OFFSET(3)] AS q3,
  APPROX_QUANTILES(sbp_value, 4)[SAFE_OFFSET(3)] - APPROX_QUANTILES(sbp_value, 4)[SAFE_OFFSET(1)] AS iqr
FROM all_sbp;