WITH PatientCohort AS (
  -- Select patients meeting the criteria: female, age 68-78, multi-trauma
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_type = 'EMERGENCY' -- Assuming multi-trauma patients are admitted via emergency
    AND EXISTS (
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'S06%' -- ICD-10 codes for multiple injuries (S06.0-S06.9)
    )
),
MedicationComplexity AS (
  -- Calculate medication complexity for each patient within the first 24 hours
  SELECT
    pc.subject_id,
    pc.hadm_id,
    COUNT(DISTINCT e.drug) AS medication_complexity
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON pc.subject_id = e.subject_id AND pc.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 24 HOUR)
  GROUP BY
    pc.subject_id,
    pc.hadm_id
),
SerotonergicRisk AS (
  -- Identify patients with serotonergic interaction risk
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.medication_complexity,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.emar` AS e_risk
        WHERE
          e_risk.subject_id = mc.subject_id
          AND e_risk.hadm_id = mc.hadm_id
          AND e_risk.charttime BETWEEN mc.admittime AND TIMESTAMP_ADD(mc.admittime, INTERVAL 24 HOUR)
          AND e_risk.medication IN ('FLUOXETINE', 'SERTRALINE', 'VENLAFAXINE', 'PAROXETINE', 'CITALOPRAM', 'ESCITALOPRAM', 'TRAMADOL', 'MEPERIDINE', 'SUMATRIPTAN', 'LINEZOLID', 'MAO INHIBITOR') -- Example serotonergic drugs
      ) THEN TRUE
      ELSE FALSE
    END AS has_serotonergic_risk
  FROM MedicationComplexity AS mc
  INNER JOIN PatientCohort AS pc
    ON mc.subject_id = pc.subject_id AND mc.hadm_id = pc.hadm_id -- Corrected JOIN condition
),
PatientData AS (
  -- Combine patient cohort data with medication complexity and serotonergic risk
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.anchor_age,
    pc.hospital_expire_flag,
    mc.medication_complexity,
    sr.has_serotonergic_risk,
    a.los -- Calculate Length of Stay (LOS)
  FROM PatientCohort AS pc
  INNER JOIN MedicationComplexity AS mc
    ON pc.subject_id = mc.subject_id AND pc.hadm_id = mc.hadm_id
  INNER JOIN SerotonergicRisk AS sr
    ON pc.subject_id = sr.subject_id AND pc.hadm_id = sr.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pc.hadm_id = a.hadm_id
),
ComplexityQuartiles AS (
  -- Calculate quartiles;