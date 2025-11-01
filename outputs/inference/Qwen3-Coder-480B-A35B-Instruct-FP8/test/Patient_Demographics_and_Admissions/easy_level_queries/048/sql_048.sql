WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  WHERE
    a.hadm_id IN (
      SELECT hadm_id
      FROM (
        SELECT
          hadm_id,
          ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
        FROM physionet-data.mimiciv_3_1_hosp.admissions
      )
      WHERE rn = 1
    )
),
hf_admissions AS (
  SELECT DISTINCT
    fa.*
  FROM
    first_admissions fa
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON fa.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.long_title LIKE '%heart failure%'
),
filtered_patients AS (
  SELECT
    hf.subject_id,
    hf.los_days
  FROM
    hf_admissions hf
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON hf.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
)
SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr
FROM
  filtered_patients;