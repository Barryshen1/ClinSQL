WITH AKI_Patients AS (
  -- Identify patients with AKI based on ICD-10 codes
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'N17%' -- AKI ICD-10 codes
    AND a.admission_type = 'EMERGENCY' -- Consider only emergency admissions for AKI
),
Medication_Complexity AS (
  -- Calculate medication complexity score for each patient
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS medication_complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.hadm_id IN (SELECT hadm_id FROM AKI_Patients)
  GROUP BY
    p.subject_id,
    p.hadm_id
),
Drug_Categories AS (
  -- Identify patients receiving CNS-depressant and nephrotoxic drugs
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.hadm_id IN (SELECT hadm_id FROM AKI_Patients)
    AND (
      p.drug LIKE '%benzod%' OR p.drug LIKE '%opioid%' OR p.drug LIKE '%sedative%' -- CNS-depressant drugs
      OR p.drug LIKE '%NSAID%' OR p.drug LIKE '%aminoglycoside%' OR p.drug LIKE '%contrast%' -- Nephrotoxic drugs
    )
),
Patient_Demographics AS (
  -- Get patient demographics
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.subject_id IN (SELECT subject_id FROM AKI_Patients)
),
Hospital_Outcomes AS (
  -- Get hospital outcomes
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los AS hospital_los,
    a.hospital_expire_flag AS hospital_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hadm_id IN (SELECT hadm_id FROM AKI_Patients)
)
SELECT
  CASE
    WHEN dc.subject_id IS NOT NULL THEN 'Both CNS-depressant and Nephrotoxic'
    ELSE 'Other AKI Patients'
  END AS drug_category,
  PERCENTILE_CONT(mc.medication_complexity_score, 0.25) AS q1_complexity,
  PERCENTILE_CONT(mc.medication_complexity_score, 0.50) AS median_complexity,
  PERCENTILE_CONT(mc.medication_complexity_score, 0.75) AS q3_complexity,
  AVG;