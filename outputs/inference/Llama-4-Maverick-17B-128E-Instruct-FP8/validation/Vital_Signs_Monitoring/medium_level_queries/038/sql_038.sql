WITH cohort AS (
  SELECT p.subject_id, ic.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON p.subject_id = ic.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 66 AND 76
),
invasively_ventilated AS (
  SELECT ic.stay_id
  FROM cohort ic
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON ic.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%Invasive Ventilation%' 
),
sbp AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON ce.stay_id = ic.stay_id
  WHERE di.label LIKE '%Systolic Blood Pressure%' 
    AND ce.stay_id IN (SELECT stay_id FROM invasively_ventilated)
    AND TIMESTAMP_DIFF(ce.charttime, ic.intime, HOUR) <= 6
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3_sbp,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1_sbp,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_sbp
FROM sbp;