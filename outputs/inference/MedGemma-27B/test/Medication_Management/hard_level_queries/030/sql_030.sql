WITH PatientCohort AS (
  -- Select patients matching the criteria: female, age 71-81, acute pancreatitis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.icd_code = 'I10.1' -- ICD-10 code for acute pancreatitis
    AND d.seq_num = 1 -- Assuming the primary diagnosis is the first one listed
),

MedicationComplexity AS (
  -- Calculate medication complexity score for each patient over the first 72 hours
  SELECT
    pc.subject_id,
    pc.hadm_id,
    COUNT(DISTINCT e.emar_id) AS medication_complexity_score
  FROM
    PatientCohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS e ON pc.subject_id = e.subject_id AND pc.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
  GROUP BY
    pc.subject_id,
    pc.hadm_id
),

Tertiles AS (
  -- Stratify patients into tertiles based on medication complexity score
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.medication_complexity_score,
    NTILE(3) OVER (ORDER BY mc.medication_complexity_score) AS tertile
  FROM
    MedicationComplexity AS mc
),

Outcomes AS (
  -- Calculate LOS, in-hospital mortality, and 30-day readmission rates
  SELECT
    t.subject_id,
    t.hadm_id,
    t.tertile,
    t.medication_complexity_score,
    -- Calculate Length of Stay (LOS)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los,
    -- Calculate In-hospital Mortality
    CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS in_hospital_mortality,
    -- Calculate 30-day Readmission
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS readmit
      WHERE readmit.subject_id = a.subject_id
        AND readmit.admittime BETWEEN TIMESTAMP_ADD(a.dischtime, INTERVAL 1 DAY) AND TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS thirty_day_readmission
  FROM
    Tertiles AS t
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON t.hadm_id = a.hadm_id
),

FinalResults AS (
  -- Aggregate results per tertile
  SELECT
    tertile,
    AVG(los) AS avg_los,
    AVG(in_hospital_mortality) AS in_hospital_mortality_rate,
    AVG(thirty_day_readmission) AS thirty_day_readmission_rate,
    COUNT(subject_id) AS patient_count
  FROM;