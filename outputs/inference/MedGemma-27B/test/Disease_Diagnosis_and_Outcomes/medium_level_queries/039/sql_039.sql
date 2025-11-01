WITH PatientAMI AS (
  -- Identify patients with AMI diagnosis
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code LIKE 'I21%' -- AMI codes
    AND d.icd_version = 9 -- Assuming ICD-9 for AMI codes
),
AdmissionAMI AS (
  -- Link patients to their admissions
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientAMI AS pa
    ON a.subject_id = pa.subject_id
),
FilteredAdmissions AS (
  -- Filter admissions based on patient demographics and admission type
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    admission_type,
    hospital_expire_flag
  FROM AdmissionAMI
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 66 AND 76
    AND admission_type = 'EMERGENCY' -- Assuming 'EMERGENCY' represents emergent admissions
),
LOSCalculation AS (
  -- Calculate Length of Stay (LOS)
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    admission_type,
    hospital_expire_flag,
    -- Calculate LOS in days
    -- If patient died, LOS is calculated from admission to death time
    -- Otherwise, LOS is calculated from admission to discharge time
    CASE
      WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admitime, DAY)
      ELSE DATE_DIFF(dischtime, admitime, DAY)
    END AS los
  FROM FilteredAdmissions
),
MortalityAnalysis AS (
  -- Calculate mortality rate and time-to-death for each LOS group
  SELECT
    admission_type,
    CASE
      WHEN los BETWEEN 1 AND 3 THEN '1-3'
      WHEN los BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_group,
    COUNTIF(hospital_expire_flag = 1) AS mortality_count,
    COUNT(hadm_id) AS total_count,
    -- Calculate median time-to-death for deceased patients
    MEDIAN(CASE WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admitime, DAY) END) AS median_time_to_death
  FROM LOSCalculation
  GROUP BY
    admission_type,
    los_group
)
-- Final result: Calculate mortality percentage
SELECT
  admission_type,
  los_group,
  (mortality_count * 100.0 / total_count) AS mortality_percentage,
  median_time_to_death
FROM MortalityAnalysis
ORDER BY
  admission_type,
  los_group;