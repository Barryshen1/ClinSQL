WITH PatientPneumonia AS (
  -- Identify patients with pneumonia diagnosis
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND d.icd_code LIKE 'J18%' -- Pneumonia codes (J18.1, J18.2, J18.8, J18.9)
),
RiskScore AS (
  -- Calculate a composite risk score for each patient
  -- This is a placeholder; the actual score calculation would be based on the study's definition
  SELECT
    subject_id,
    -- Example: Score based on age and presence of comorbidities (e.g., CHF, COPD)
    -- Replace with the actual risk score calculation
    (
      CASE
        WHEN anchor_age < 85 THEN 1
        ELSE 2
      END
    ) +
    (
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
          WHERE
            d2.subject_id = PatientPneumonia.subject_id
            AND d2.icd_code LIKE 'I50%' -- Congestive heart failure
        ) THEN 1
        ELSE 0
      END
    ) +
    (
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d3
          WHERE
            d3.subject_id = PatientPneumonia.subject_id
            AND d3.icd_code LIKE 'J44%' -- Chronic obstructive pulmonary disease
        ) THEN 1
        ELSE 0
      END
    ) AS composite_risk_score
  FROM PatientPneumonia
),
PatientRiskQuintiles AS (
  -- Assign patients to risk quintiles
  SELECT
    subject_id,
    composite_risk_score,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
  FROM RiskScore
),
AdmissionData AS (
  -- Get admission details and calculate LOS
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate Length of Stay (LOS)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientRiskQuintiles)
),
ComplicationData AS (
  -- Identify cardiovascular and neurologic complications
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE
      WHEN d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I25%' THEN 1 -- Acute myocardial infarction, Atherosclerosis
      ELSE 0
    END AS cardiovascular_complication,
    CASE
      WHEN d.icd_code LIKE 'G45%' OR d.icd_code LIKE 'I69%' THEN 1 -- Stroke, Cerebral infarction
      ELSE 0
    END AS neurologic_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientRiskQuintiles)
),
MortalityData AS (
  -- Determine 30-day mortality
  SELECT
    a.subject_id,
    a.hadm_id,;