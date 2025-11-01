WITH patient_icustay AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
  ON 
    p.subject_id = ic.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
),
icu_length_of_stay AS (
  SELECT 
    stay_id,
    TIMESTAMP_DIFF(outtime, intime, HOUR) AS icu_los_hours
  FROM 
    patient_icustay
)
SELECT 
  APPROX_QUANTILES(icu_los_hours, 1000)[500] AS median_icu_los_hours
FROM 
  icu_length_of_stay;