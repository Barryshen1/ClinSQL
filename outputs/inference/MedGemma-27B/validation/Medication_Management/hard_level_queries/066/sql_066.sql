WITH PatientCohort AS (
  -- Select patients meeting the criteria: male, age 43-53, transplant diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    d.long_title AS diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND d.icd_code LIKE 'Z94%' -- ICD-10 codes for solid organ transplant follow-up
    AND d.icd_version = 10
  GROUP BY
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    d.long_title
), MedicationComplexity AS (
  -- Calculate medication complexity score for each patient
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    COUNT(DISTINCT e.drug) AS num_unique_meds,
    COUNT(DISTINCT e.route) AS num_unique_routes,
    COUNT(DISTINCT e.drug_type) AS num_unique_drug_types
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON pc.subject_id = e.subject_id AND pc.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN pc.admittime AND DATE_ADD(pc.admittime, INTERVAL 7 DAY)
  GROUP BY
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime
), ComplexityScore AS (
  -- Calculate the medication complexity score
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.admittime,
    mc.dischtime,
    (mc.num_unique_meds + mc.num_unique_routes + mc.num_unique_drug_types) AS complexity_score
  FROM MedicationComplexity AS mc
), CohortWithScore AS (
  -- Combine patient cohort with complexity score
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.admittime,
    cs.dischtime,
    cs.complexity_score
  FROM ComplexityScore AS cs
), QuartileAnalysis AS (
  -- Calculate quartiles based on complexity score
  SELECT
    cws.subject_id,
    cws.hadm_id,
    cws.admittime,
    cws.dischtime,
    cws.complexity_score,
    NTILE(4) OVER (ORDER BY cws.complexity_score) AS complexity_quartile
  FROM CohortWithScore AS cws
), FinalAnalysis AS (
  -- Calculate metrics per quartile
  SELECT
    complexity_quartile,
    COUNT(DISTINCT subject_id) AS n,
    AVG(complexity_score) AS mean_score,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality,
    AVG(CASE WHEN r.readmitted = 1 THEN 1 ELSE 0 END) AS thirty_day_readmission
  FROM QuartileAnalysis AS qa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON qa.hadm_id = a.hadm_id
  LEFT JOIN (
    SELECT
      a.subject_id,
      a.hadm_;