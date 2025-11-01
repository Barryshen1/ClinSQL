WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    a.dischtime IS NOT NULL
),
filtered_admissions AS (
  SELECT
    pa.los_days
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.hadm_id = d.hadm_id
  WHERE
    pa.gender = 'F'
    AND pa.age_at_admission BETWEEN 40 AND 50
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND (
      d.icd_code LIKE 'I20%' OR
      d.icd_code LIKE 'I21%' OR
      d.icd_code LIKE 'I22%' OR
      d.icd_code LIKE 'I24%'
    )
)
SELECT
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25_los
FROM
  filtered_admissions;