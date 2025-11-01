WITH
-- Get first AMI admission for each patient
first_ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE
    a.subject_id IN (
      SELECT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.patients`
      WHERE gender = 'M' AND anchor_age BETWEEN 40 AND 50
    )
    AND (
      -- AMI ICD-9 codes
      (d.icd_version = 9 AND d.icd_code LIKE '410.%')
      OR
      -- AMI ICD-10 codes
      (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
    )
    AND NOT EXISTS (
      -- Exclude patients with shock
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` shock
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` shock_diag
        ON shock.icd_code = shock_diag.icd_code AND shock.icd_version = shock_diag.icd_version
      WHERE
        shock.subject_id = a.subject_id AND shock.hadm_id = a.hadm_id
        AND (
          (shock.icd_version = 9 AND shock.icd_code = '785.51')
          OR
          (shock.icd_version = 10 AND shock.icd_code = 'R57.0')
        )
    )
    AND NOT EXISTS (
      -- Exclude patients with respiratory failure
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` resp
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` resp_diag
        ON resp.icd_code = resp_diag.icd_code AND resp.icd_version = resp_diag.icd_version
      WHERE
        resp.subject_id = a.subject_id AND resp.hadm_id = a.hadm_id
        AND (
          (resp.icd_version = 9 AND resp.icd_code = '518.81')
          OR
          (resp.icd_version = 10 AND resp.icd_code = 'J96.0')
        )
    )
),

-- Get only the first AMI admission per patient
ami_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM
    first_ami_admissions
  WHERE
    admission_rank = 1
),

-- Calculate LOS and day-1 ICU status
patient_outcomes AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    MAX(CASE WHEN t.intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
             AND t.outtime >= TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
             AND t.careunit LIKE '%ICU%'
             THEN 1 ELSE 0 END) AS day1_icu
  FROM
    ami_admissions a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  GROUP BY
    a.subject_id, a.hadm_id, a.hospital_expire_flag, los_days
)

-- Final aggregation
SELECT
  CASE WHEN day1_icu = 1 THEN 'Yes' ELSE 'No' END AS day1_icu_status,
  CASE WHEN los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_category,
  COUNT(*) AS patient_count,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percentage,
  ROUND(AVG(los_days), 1) AS median_los_days
FROM
  patient_outcomes
GROUP BY
  day1_icu_status, los_category
ORDER BY
  day1_icu_status, los_category;