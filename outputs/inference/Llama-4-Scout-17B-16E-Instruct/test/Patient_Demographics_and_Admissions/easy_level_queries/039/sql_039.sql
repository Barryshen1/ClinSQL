WITH patient_info AS (
  SELECT 
    subject_id,
    gender,
    anchor_age,
    dod
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients`
),
icu_stays_info AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    first_careunit,
    last_careunit,
    intime,
    outtime,
    los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),
filtered_patients AS (
  SELECT 
    pi.subject_id,
    pi.anchor_age,
    pi.gender
  FROM 
    patient_info pi
  WHERE 
    pi.gender = 'M'
    AND pi.anchor_age BETWEEN 43 AND 53
),
first_icu_admission AS (
  SELECT 
    fs.subject_id,
    MIN(fs.intime) AS first_icu_intime
  FROM 
    icu_stays_info fs
  GROUP BY 
    fs.subject_id
),
icu_los AS (
  SELECT 
    fs.subject_id,
    fs.stay_id,
    fs.intime,
    fs.outtime,
    DATE_DIFF(fs.outtime, fs.intime, DAY) AS icu_los_days
  FROM 
    icu_stays_info fs
  JOIN 
    first_icu_admission fia ON fs.subject_id = fia.subject_id AND fs.intime = fia.first_icu_intime
)
SELECT 
  APPROX_QUANTILES(icu_los_days, 100)[OFFSET(25)] AS percentile_25_icu_los
FROM 
  icu_los;