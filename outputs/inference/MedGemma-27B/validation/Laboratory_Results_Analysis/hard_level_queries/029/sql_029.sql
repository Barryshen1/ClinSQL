WITH PatientCohort AS (
  -- Select patients matching the criteria: female, age 50-60, with hyperosmolar hyperglycemic state (HHS)
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hadm_id IN (
      -- Find admissions with HHS diagnosis
      SELECT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        icd_code = '252.81' -- ICD-9 code for Hyperosmolar hyperglycemic state
    )
),
LabInstabilityScore AS (
  -- Calculate the laboratory instability score for each patient within the first 48 hours
  SELECT
    pc.subject_id,
    pc.hadm_id,
    AVG(
      CASE
        WHEN le.valuenum IS NULL OR prev_le.valuenum IS NULL THEN 0
        ELSE
          ABS(le.valuenum - prev;