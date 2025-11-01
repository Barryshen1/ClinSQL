WITH amiodarone_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE
    LOWER(p.drug) LIKE '%amiodarone%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
),
patient_admissions AS (
  SELECT
    pt.subject_id,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    adm.hadm_id,
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
  WHERE pt.gender = 'F'
),
filtered_prescriptions AS (
  SELECT
    ap.duration_days
  FROM amiodarone_prescriptions ap
  INNER JOIN patient_admissions pa
    ON ap.subject_id = pa.subject_id
    AND ap.hadm_id = pa.hadm_id
  WHERE
    pa.anchor_age + (EXTRACT(YEAR FROM pa.admittime) - pa.anchor_year) BETWEEN 59 AND 69
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_duration_days
FROM filtered_prescriptions;