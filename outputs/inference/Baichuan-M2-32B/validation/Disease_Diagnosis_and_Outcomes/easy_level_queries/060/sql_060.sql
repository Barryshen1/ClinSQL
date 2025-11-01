WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(
      a.admittime,
      DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR),
      YEAR
    ) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (a.hospital_expire_flag = 1 AND a.deathtime IS NOT NULL)
       OR (a.hospital_expire_flag = 0 AND a.dischtime IS NOT NULL)
),
admissions_with_diagnosis AS (
  SELECT
    pa.*,
    d.icd_code
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.subject_id = d.subject_id AND pa.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'K25%'
),
los_data AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(
      CASE
        WHEN hospital_expire_flag = 1 THEN deathtime
        ELSE dischtime
      END,
      admittime,
      DAY
    ) AS los_days
  FROM admissions_with_diagnosis
  WHERE age_at_admission BETWEEN 74 AND 84
)
SELECT
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(24)] AS p25_los
FROM los_data;