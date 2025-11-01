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
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.icd_code LIKE 'I21%' -- AMI codes
),
MedicationComplexity AS (
  -- Calculate medication complexity score for the first 24 hours
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.drug) AS medication_complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS h
  WHERE
    h.charttime BETWEEN h.admittime AND h.admittime + INTERVAL '24' HOUR
  GROUP BY
    h.subject_id,
    h.hadm_id
),
AdmissionData AS (
  -- Combine patient and admission data
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    mc.medication_complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN MedicationComplexity AS mc
    ON a.hadm_id = mc.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientAMI)
),
LOSCalculation AS (
  -- Calculate Length of Stay (LOS)
  SELECT
    hadm_id,
    subject_id,
    medication_complexity_score,
    -- Calculate LOS in days
    (TIMESTAMP_DIFF(dischtime, admitime, DAY) + 1) AS los_days
  FROM AdmissionData
),
MortalityCalculation AS (
  -- Calculate in-hospital mortality
  SELECT
    hadm_id,
    subject_id,
    medication_complexity_score,
    CASE
      WHEN hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS in_hospital_mortality
  FROM AdmissionData
),
ReadmissionCalculation AS (
  -- Calculate 30-day readmission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    CASE
      WHEN COUNT(a2.hadm_id) > 0 THEN 1
      ELSE 0
    END AS readmission_30_day
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON a.subject_id = a2.subject_id
    AND a2.admittime > a.dischtime
    AND a2.admittime <= a; -- Error is here;