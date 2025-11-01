WITH
  -- Female patients aged 69–79
  female_patients AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'F'
      AND anchor_age BETWEEN 69 AND 79
  ),

  -- Admissions for those patients
  patient_admissions AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      JOIN female_patients fp
        ON a.subject_id = fp.subject_id
  ),

  -- Admissions with UGIB diagnosis (ICD-9 578.0 or 578.9)
  ugib_admissions AS (
    SELECT DISTINCT
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
      d.icd_version = 9
      AND d.icd_code IN ('5780', '5789')
  ),

  -- Admissions with COPD exacerbation diagnosis (ICD-9 491.21)
  copd_exac_admissions AS (
    SELECT DISTINCT
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
      d.icd_version = 9
      AND d.icd_code = '49121'
  ),

  -- Admissions meeting both UGIB and COPD exacerbation
  target_admissions AS (
    SELECT
      pa.subject_id,
      pa.hadm_id,
      pa.admittime,
      pa.dischtime,
      TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days
    FROM
      patient_admissions pa
      JOIN ugib_admissions u
        ON pa.hadm_id = u.hadm_id
      JOIN copd_exac_admissions c
        ON pa.hadm_id = c.hadm_id
  )

-- Compute the median LOS
SELECT
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_hospital_los_days
FROM
  target_admissions;