WITH
-- 1. Identify the base cohort: Female, 76-86, with a diagnosis of cardiac arrest
Cohort AS (
  SELECT DISTINCT -- Use DISTINCT to handle multiple 'cardiac arrest' diagnoses for one admission
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(d_dx.long_title) LIKE '%cardiac arrest%'
),

-- 2. Calculate medication complexity (count of unique drugs in first 7 days) for each admission
MedComplexity AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_complexity_score
  FROM
    Cohort AS c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON c.hadm_id = pr.hadm_id
    -- Filter prescriptions to the first 7 days of the admission
    AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    c.hadm_id
),

-- 3. Find the next admission time for each patient to check for readmissions
NextAdmission AS (
  SELECT
    hadm_id,
    subject_id,
    dischtime,
    -- Get the admittime of the next admission for the same patient
    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- 4. Combine all data, calculate LOS, readmission flag, and assign quintiles
StagedData AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    mc.med_complexity_score,
    na.next_admittime,
    -- A readmission is true if the next admission is within 30 days of discharge
    CASE
      WHEN na.next_admittime IS NOT NULL AND DATETIME_DIFF(na.next_admittime, c.dischtime, DAY) BETWEEN 0 AND 30
      THEN 1
      ELSE 0
    END AS readmitted_30d_flag,
    -- Stratify by medication complexity into 5 groups
    NTILE(5) OVER (ORDER BY mc.med_complexity_score) AS med_complexity_quintile
  FROM
    Cohort AS c
  INNER JOIN
    MedComplexity AS mc
    ON c.hadm_id = mc.hadm_id
  LEFT JOIN
    NextAdmission AS na
    ON c.hadm_id = na.hadm_id
)

-- 5. Final aggregation to report metrics per quintile
SELECT
  med_complexity_quintile,
  COUNT(hadm_id) AS patient_count,
  ROUND(AVG(med_complexity_score), 2) AS avg_med_complexity,
  MIN(med_complexity_score) AS min_med_complexity,
  MAX(med_complexity_score) AS max_med_complexity,
  ROUND(AVG(los_days), 2) AS avg_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(readmitted_30d_flag) * 100, 2) AS readmission_30d_pct
FROM
  StagedData
GROUP BY
  med_complexity_quintile
ORDER BY
  med_complexity_quintile;