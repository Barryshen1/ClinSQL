WITH troponin_t AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_trop_t AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_t tt ON le.itemid = tt.itemid
  WHERE le.valuenum IS NOT NULL
),
initial_trop_t AS (
  SELECT subject_id, hadm_id, valuenum AS first_trop_t_value
  FROM first_trop_t
  WHERE rn = 1
),
patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
),
cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_age pa
    ON a.subject_id = pa.subject_id
  INNER JOIN initial_trop_t itt
    ON a.hadm_id = itt.hadm_id
  WHERE
    pa.gender = 'M'
    AND pa.age_at_admission BETWEEN 73 AND 83
    AND itt.first_trop_t_value > 0.01  -- elevated Troponin T
)
SELECT
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate
FROM cohort;