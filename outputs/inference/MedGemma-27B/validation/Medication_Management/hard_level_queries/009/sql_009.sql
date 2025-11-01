WITH PatientAKI AS (
  -- Identify patients with AKI based on ICD-10 codes
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'N17%' -- AKI ICD-10 codes
), PatientDemographics AS (
  -- Filter patients based on age and gender
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 84 AND 94
), AKIPatientAdmissions AS (
  -- Combine AKI patients with demographic filters
  SELECT
    pa.subject_id,
    pa.hadm_id
  FROM PatientAKI AS pa
  JOIN PatientDemographics AS pd
    ON pa.subject_id = pd.subject_id
), MedicationComplexity AS (
  -- Calculate medication complexity score for each admission
  SELECT
    hadm_id,
    COUNT(DISTINCT e.drug) AS medication_complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS e
  GROUP BY
    hadm_id
), QuintileMedicationComplexity AS (
  -- Assign patients to quintiles based on medication complexity score
  SELECT
    hadm_id,
    medication_complexity_score,
    NTILE(5) OVER (ORDER BY medication_complexity_score) AS medication_complexity_quintile
  FROM MedicationComplexity
), AdmissionLOS AS (
  -- Calculate Length of Stay (LOS) for each admission
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
), InpatientMortality AS (
  -- Determine inpatient mortality for each admission
  SELECT
    hadm_id,
    CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END AS inpatient_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
), Readmission AS (
  -- Determine 30-day readmission for each admission
  SELECT
    a.hadm_id,
    CASE WHEN COUNT(a.hadm_id) > 0 THEN 1 ELSE 0 END AS readmission_30_day
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.transfers` AS t
    ON a.hadm_id = t.hadm_id
  WHERE
    t.transfer_id = 1 AND t.careunit = 'READMIT' AND t.outtime BETWEEN a.dischtime AND TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
  GROUP BY
    a;