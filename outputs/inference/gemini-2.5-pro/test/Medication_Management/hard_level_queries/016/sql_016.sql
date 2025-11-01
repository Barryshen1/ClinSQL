WITH
-- Step 1: Identify the base cohort of female patients aged 80-90 at admission.
patient_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (
      DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age
    ) BETWEEN 80 AND 90
),

-- Step 2: Filter the base cohort for admissions with a diagnosis of hepatic failure.
hepatic_failure_adms AS (
  SELECT DISTINCT
    pc.subject_id,
    pc.hadm_id
  FROM
    patient_cohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON pc.hadm_id = dx.hadm_id
  WHERE
    dx.icd_code IN (
      -- ICD-9 codes for hepatic failure
      '5722',  -- Hepatic coma
      '570',   -- Acute and subacute necrosis of liver
      -- ICD-10 codes for hepatic failure
      'K7200', -- Acute and subacute hepatic failure without coma
      'K7201', -- Acute and subacute hepatic failure with coma
      'K7210', -- Chronic hepatic failure without coma
      'K7211', -- Chronic hepatic failure with coma
      'K7290', -- Hepatic failure, unspecified without coma
      'K7291'  -- Hepatic failure, unspecified with coma
    )
),

-- Step 3: Calculate a 7-day medication complexity score for all admissions.
-- This is defined as the count of distinct medications in the first 7 days.
med_complexity AS (
  SELECT
    pr.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pr.hadm_id = a.hadm_id
  WHERE
    pr.starttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 7 DAY)
  GROUP BY
    pr.hadm_id
),

-- Step 4: Calculate a 30-day readmission flag for all admissions.
readmission_flag AS (
  SELECT
    hadm_id,
    -- Check if the next admission is within 30 days of discharge
    CASE
      WHEN next_admittime IS NOT NULL AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmitted_30_days
  FROM (
    SELECT
      hadm_id,
      dischtime,
      subject_id,
      admittime,
      -- Get the admission time of the next hospital stay for the same patient
      LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
  )
),

-- Step 5: Combine the cohort with the calculated features (LOS, complexity, readmission).
cohort_features AS (
  SELECT
    hfa.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    COALESCE(mc.med_complexity_score, 0) AS med_complexity_score,
    COALESCE(rf.readmitted_30_days, 0) AS readmitted_30_days
  FROM
    hepatic_failure_adms AS hfa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON hfa.hadm_id = a.hadm_id
  LEFT JOIN
    med_complexity AS mc
    ON hfa.hadm_id = mc.hadm_id
  LEFT JOIN
    readmission_flag AS rf
    ON hfa.hadm_id = rf.hadm_id
  WHERE
    a.dischtime IS NOT NULL AND a.dischtime >= a.admittime -- Ensure valid discharge time and non-negative LOS
),

-- Step 6: Stratify the cohort into tertiles based on the medication complexity score.
cohort_tertiles AS (
  SELECT
    hadm_id,
    los,
    hospital_expire_flag,
    readmitted_30_days,
    med_complexity_score,
    NTILE(3) OVER (ORDER BY med_complexity_score) AS score_tertile
  FROM
    cohort_features
)

-- Final Step: Aggregate the results by tertile and calculate the required metrics.
SELECT
  score_tertile,
  COUNT(hadm_id) AS number_of_patients,
  MIN(med_complexity_score) AS min_med_score,
  MAX(med_complexity_score) AS max_med_score,
  AVG(los) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate_percent,
  AVG(readmitted_30_days) * 100 AS thirty_day_readmission_rate_percent
FROM
  cohort_tertiles
GROUP BY
  score_tertile
ORDER BY
  score_tertile;