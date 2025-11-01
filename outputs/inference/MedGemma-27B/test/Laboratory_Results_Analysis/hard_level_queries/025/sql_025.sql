WITH PatientCohort AS (
  -- Select patients matching the criteria: female, age 48-58, hemorrhagic stroke
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code LIKE 'I60%' -- Hemorrhagic stroke ICD-10 codes start with I60
    AND d.seq_num = 1 -- Assuming the primary diagnosis is the first one listed
),

LabInstabilityScore AS (
  -- Calculate the lab instability score for each patient
  SELECT
    pc.subject_id,
    pc.hadm_id,
    COUNT(DISTINCT le.itemid) AS lab_instability_score
  FROM
    PatientCohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le ON pc.subject_id = le.subject_id AND pc.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL -- Consider only numeric lab values
    AND le.valueuom IS NOT NULL
    AND le.flag IS NULL -- Exclude flagged lab results
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper) -- Critical value check
  GROUP BY
    pc.subject_id,
    pc.hadm_id
),

P90Threshold AS (
  -- Calculate the 90th percentile of the lab instability score
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.90) AS p90_threshold
  FROM
    LabInstabilityScore
),

HighInstabilityCohort AS (
  -- Select patients with a lab instability score >= P90 threshold
  SELECT
    lis.subject_id,
    lis.hadm_id,
    lis.lab_instability_score
  FROM
    LabInstabilityScore AS lis
  CROSS JOIN
    P90Threshold AS p90
  WHERE
    lis.lab_instability_score >= p90.p90_threshold
),

AgeMatchedCohort AS (
  -- Select age-matched controls
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.disch;