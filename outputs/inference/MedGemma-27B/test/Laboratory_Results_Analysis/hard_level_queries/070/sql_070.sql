WITH PatientCohort AS (
  -- Select patients meeting the criteria: male, age 40-50, hemorrhagic stroke
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admittime BETWEEN '2150-01-01' AND '2150-12-31' -- Filter for relevant time range if needed
    AND EXISTS (
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I60%' -- ICD-10 codes for intracerebral hemorrhage
    )
), LabInstability AS (
  -- Calculate the 72-hour lab instability score for each patient
  SELECT
    pc.subject_id,
    pc.hadm_id,
    COUNT(DISTINCT le.itemid) AS lab_instability_score
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pc.subject_id = le.subject_id AND pc.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL -- Consider only numeric lab values
    AND le.valueuom IS NOT NULL
    AND le.flag IS NULL -- Exclude flagged labs
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper) -- Check if the value is outside the reference range
  GROUP BY
    pc.subject_id,
    pc.hadm_id
), QuartileAnalysis AS (
  -- Stratify patients into quartiles based on their lab instability score
  SELECT
    li.subject_id,
    li.hadm_id,
    li.lab_instability_score,
    NTILE(4) OVER (ORDER BY li.lab_instability_score) AS quartile
  FROM LabInstability AS li
), CohortStats AS (
  -- Calculate LOS and mortality for the cohort
  SELECT
    qa.subject_id,
    qa.hadm_id,
    qa.quartile,
    qa.lab_instability_score,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los,
    a.hospital_expire_flag AS mortality
  FROM QuartileAnalysis AS qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON qa.hadm_id = a.hadm_id
)
-- Final selection and aggregation
SELECT
  qa.quartile,
  AVG(cs.los) AS avg_los,
  AVG(CASE WHEN cs.mortality = TRUE THEN 1 ELSE 0 END) AS mortality_rate,
  AVG(cs.lab_instability_score) AS avg_lab_instability_score,
  COUNT(DISTINCT cs.subject_id) AS patient_count
FROM CohortStats AS cs
INNER JOIN QuartileAnalysis AS qa
  ON cs.subject_id = qa.subject_id AND cs.hadm_id = qa.hadm_id
GROUP BY
  qa.quartile
ORDER BY
  qa.quartile;