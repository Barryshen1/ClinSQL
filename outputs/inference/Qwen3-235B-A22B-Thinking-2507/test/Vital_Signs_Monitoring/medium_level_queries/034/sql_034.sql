WITH patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),

icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    pa.age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patient_age pa
    ON i.subject_id = pa.subject_id AND i.hadm_id = pa.hadm_id
  WHERE pa.gender = 'M'
    AND pa.age_at_admission BETWEEN 37 AND 47
),

ventilated_stays AS (
  SELECT DISTINCT
    is_.subject_id,
    is_.hadm_id,
    is_.stay_id
  FROM icu_stays is_
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON is_.subject_id = ce.subject_id 
    AND is_.hadm_id = ce.hadm_id 
    AND is_.stay_id = ce.stay_id
  WHERE ce.itemid IN (225468, 225469)
),

max_diastolic_bp AS (
  SELECT
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id,
    MAX(ce.valuenum) AS max_diastolic_bp
  FROM ventilated_stays vs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON vs.subject_id = ce.subject_id 
    AND vs.hadm_id = ce.hadm_id 
    AND vs.stay_id = ce.stay_id
  WHERE ce.itemid IN (220051, 220180, 225310)
    AND ce.valuenum IS NOT NULL
  GROUP BY vs.subject_id, vs.hadm_id, vs.stay_id
)

SELECT
  APPROX_QUANTILES(mdb.max_diastolic_bp, 100)[OFFSET(25)] AS percentile_25
FROM max_diastolic_bp mdb;