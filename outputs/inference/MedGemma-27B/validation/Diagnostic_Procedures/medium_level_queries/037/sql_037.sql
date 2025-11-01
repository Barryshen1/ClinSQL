WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    icd_code,
    seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
), ProcedureInfo AS (
  SELECT
    hadm_id,
    hcpcs_cd,
    seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), RadiographyInfo AS (
  SELECT
    hadm_id,
    hcpcs_cd
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    hcpcs_cd LIKE '7%' -- Radiography/CT codes start with 7
), StayDuration AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admitime, DAY) AS los
  FROM
    AdmissionInfo
)
SELECT
  CASE
    WHEN d.seq_num = 1 THEN 'Primary'
    ELSE 'Secondary'
  END AS ami_type,
  CASE
    WHEN sd.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN sd.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other'
  END AS stay_duration,
  PERCENTILE_CONT(COUNT(r.hcpcs_cd), 0.5) AS median_radiography_cts,
  PERCENTILE_CONT(COUNT(r.hcpcs_cd), 0.25) AS iqr_lower,
  PERCENTILE_CONT(COUNT(r.hcpcs_cd), 0.75) AS iqr_upper
FROM
  PatientInfo AS p
JOIN
  DiagnosisInfo AS d ON p.subject_id = d.subject_id
JOIN
  RadiographyInfo AS r ON p.hadm_id = r.hadm_id
JOIN
  StayDuration AS sd ON p.hadm_id = sd.hadm_id
WHERE
  p.gender = 'M' AND p.anchor_age = 48 AND d.icd_code = '410' -- AMI code
GROUP BY
  ami_type,
  stay_duration
ORDER BY
  ami_type,
  stay_duration;