WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'SURG'
    AND p.anchor_age BETWEEN 51 AND 61
), MedicationComplexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT emar_detail.medication) AS unique_drugs,
    SUM(CASE
      WHEN emar_detail.medication IN ('heparin', 'warfarin', 'enoxaparin', 'rivaroxaban', 'apixaban', 'dabigatran') THEN 1
      ELSE 0
    END) AS anticoagulants,
    SUM(CASE
      WHEN emar_detail.medication IN ('morphine', 'fentanyl', 'hydromorphone', 'oxycodone', 'methadone') THEN 1
      ELSE 0
    END) AS opioids,
    SUM(CASE
      WHEN emar_detail.medication IN ('metformin', 'glipizide', 'glyburide', 'insulin') THEN 1
      ELSE 0
    END) AS antidiabetics,
    SUM(CASE
      WHEN emar_detail.medication IN ('lisinopril', 'enalapril', 'ramipril', 'losartan', 'valsartan') THEN 1
      ELSE 0
    END) AS antihypertensives,
    SUM(CASE
      WHEN emar_detail.medication IN ('atorvastatin', 'simvastatin', 'rosuvastatin') THEN 1
      ELSE 0
    END) AS statins
  FROM `physionet-data.mimiciv_3_1_hosp.emar_detail` AS emar_detail
  WHERE
    emar_detail.medication IS NOT NULL
  GROUP BY
    subject_id,
    hadm_id
), ComplexityScore AS (
  SELECT
    subject_id,
    hadm_id,
    unique_drugs + anticoagulants + opioids + antidiabetics + antihypertensives + statins AS complexity_score
  FROM MedicationComplexity
), Quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    complexity_score,
    NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
  FROM ComplexityScore
), AdmissionOutcomes AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.admittime,
    pi.dischtime,
    pi.deathtime,
    q.complexity_quartile,
    q.complexity_score,
    -- Calculate LOS
    TIMESTAMP_DIFF(pi.dischtime, pi.admittime, DAY) AS los,
    -- Calculate In-hospital mortality
    CASE
      WHEN pi.deathtime IS NOT NULL AND pi.deathtime <= pi.dischtime THEN 1
      ELSE 0
    END AS in_hospital_mortality,
    -- Calculate 30-day readmission
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS readm
        WHERE readm.subject_id = pi.subject_id
          AND readm.admittime BETWEEN pi.dischtime AND TIMESTAMP_ADD(pi.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS thirty_day_readmission
  FROM PatientInfo AS pi
  INNER JOIN Quartiles AS q
    ON pi.subject_id = q.subject_id AND pi.hadm_id = q.hadm_id
), FinalResults AS (
  SELECT
    complexity_quartile,
    COUNT(subject_id) AS count,
    AVG(los) AS avg_los,
    SUM(in_hospital_mortality) / COUNT(subject_id);