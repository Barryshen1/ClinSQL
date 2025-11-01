WITH first_admissions AS (
  -- Get the first admission for each patient
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN (
    -- Subquery to find the first hadm_id for each subject_id
    SELECT
      subject_id,
      MIN(hadm_id) AS first_hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY
      subject_id
  ) first ON a.subject_id = first.subject_id AND a.hadm_id = first.first_hadm_id
),

cabg_patients AS (
  -- Identify patients who underwent CABG during their first admission
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    first_admissions a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON a.hadm_id = proc.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc ON proc.icd_code = d_proc.icd_code
  WHERE
    p.gender = 'F'
    AND (
      -- ICD-9 codes for CABG
      (proc.icd_version = 9 AND proc.icd_code LIKE '36.1%')
      OR
      -- ICD-10 codes for CABG
      (proc.icd_version = 10 AND proc.icd_code LIKE '2A05%')
    )
    AND (
      -- Age at admission between 35 and 45
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 35 AND 45
    )
)

-- Calculate in-hospital mortality rate
SELECT
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2
  ) AS mortality_rate_percentage
FROM
  cabg_patients;