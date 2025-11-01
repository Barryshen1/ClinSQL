WITH SepsisPatients AS (
  -- Identify patients with sepsis (excluding septic shock) based on Sepsis-3 criteria
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%sepsis%'
    AND a.hospital_expire_flag = 0 -- Exclude septic shock (hospital_expire_flag = 1)
),
PatientDemographics AS (
  -- Get patient demographics and comorbidities
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    -- Check for CKD (ICD-10 codes)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_ckd
        WHERE di_ckd.subject_id = p.subject_id
          AND di_ckd.icd_code IN ('N181', 'N182', 'N183', 'N184', 'N185', 'N186', 'N189')
      ) THEN 1
      ELSE 0
    END AS has_ckd,
    -- Check for Diabetes (ICD-10 codes)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_dm
        WHERE di_dm.subject_id = p.subject_id
          AND di_dm.icd_code IN ('E10', 'E11', 'E13', 'E14')
      ) THEN 1
      ELSE 0
    END AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
),
HospitalStayInfo AS (
  -- Get hospital stay information including LOS
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate Length of Stay (LOS) in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
)
SELECT
  los_quartile,
  COUNT(DISTINCT subject_id) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
  (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id)) * 100 AS mortality_rate,;