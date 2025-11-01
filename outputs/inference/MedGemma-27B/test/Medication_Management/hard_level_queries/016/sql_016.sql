WITH PatientCohort AS (
  -- Select patients meeting the criteria: female, age 80-90, hepatic failure
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    d.icd_code,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND d.icd_code LIKE 'K7%' -- Hepatic failure codes (K70-K76)
    AND d.seq_num = 1 -- Primary diagnosis
),
MedicationComplexity AS (
  -- Calculate medication complexity score for each patient
  SELECT
    p.subject_id,
    COUNT(DISTINCT e.drug) AS medication_complexity_score
  FROM PatientCohort AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON p.subject_id = e.subject_id
  WHERE
    e.charttime BETWEEN p.admittime AND p.dischtime
  GROUP BY
    p.subject_id
),
CohortWithComplexity AS (
  -- Combine patient cohort with medication complexity score
  SELECT
    p.subject_id,
    p.admittime,
    p.dischtime,
    p.deathtime,
    mc.medication_complexity_score
  FROM PatientCohort AS p
  INNER JOIN MedicationComplexity AS mc
    ON p.subject_id = mc.subject_id
),
Tertiles AS (
  -- Stratify cohort into tertiles based on medication complexity score
  SELECT
    subject_id,
    medication_complexity_score,
    NTILE(3) OVER (ORDER BY medication_complexity_score) AS tertile
  FROM CohortWithComplexity
),
Outcomes AS (
  -- Calculate LOS, in-hospital mortality, and 30-day readmission rates
  SELECT
    t.subject_id,
    t.tertile,
    t.medication_complexity_score,
    -- Calculate Length of Stay (LOS)
    TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY) AS los,
    -- Calculate In-hospital Mortality
    CASE
      WHEN t.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS in_hospital_mortality,
    -- Calculate 30-day Readmission
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = t.subject_id
          AND a2.admittime BETWEEN TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY) AND TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY + INTERVAL 1 DAY)
      ) THEN 1
      ELSE 0
    END AS thirty_day_readmission
  FROM Tertiles AS t
)
-- Final aggregation to report outcomes per tertile
SELECT
  tertile,
  COUNT(subject_id) AS cohort_size,
  AVG(los) AS avg_los,
  AVG(in_hospital_mortality) AS in_hospital_mortality_rate,
  AVG(thirty_day_readmission) AS thirty_day_readmission_rate
FROM Outcomes
GROUP BY
  tertile
ORDER BY
  tertile;