WITH
-- Step 1: Define the base cohort of male patients aged 57-67
base_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    -- Use deathtime if dischtime is null to define the end of the stay
    COALESCE(a.dischtime, a.deathtime) AS endtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
),

-- Step 2: Identify hospital admissions with both diabetes and acute HF diagnoses
hadm_with_conditions AS (
  -- Admissions with a diabetes diagnosis
  SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250')
    OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13'))
  INTERSECT DISTINCT
  -- Admissions with an acute heart failure diagnosis
  SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code IN ('4280', '4281', '42821', '42823', '42831', '42833', '42841', '42843'))
    OR (icd_version = 10 AND icd_code IN ('I501', 'I509', 'I5021', 'I5023', 'I5031', 'I5033', 'I5041', 'I5043'))
),

-- Step 3: Create the final cohort by joining the base cohort with the condition-filtered admissions
final_cohort AS (
  SELECT
    bc.hadm_id,
    bc.admittime,
    bc.endtime
  FROM
    base_cohort AS bc
  INNER JOIN
    hadm_with_conditions AS hwc
    ON bc.hadm_id = hwc.hadm_id
  -- Ensure the endtime is valid and after admittime for interval calculations
  WHERE bc.endtime > bc.admittime
),

-- Step 4: For each patient in the final cohort, flag if a GLP-1 was initiated in the specified time windows
cohort_initiations AS (
  SELECT
    fc.hadm_id,
    MAX(
      CASE
        WHEN pr.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 72 HOUR)
        THEN 1
      ELSE 0
      END
    ) AS initiated_first_72h,
    MAX(
      CASE
        WHEN pr.starttime BETWEEN DATETIME_SUB(fc.endtime, INTERVAL 24 HOUR) AND fc.endtime
        THEN 1
      ELSE 0
      END
    ) AS initiated_final_24h
  FROM
    final_cohort AS fc
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON fc.hadm_id = pr.hadm_id
    -- Filter for GLP-1 prescriptions in the JOIN condition
    AND (
      LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%ozempic%' OR LOWER(pr.drug) LIKE '%rybelsus%' OR LOWER(pr.drug) LIKE '%wegovy%'
      OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%victoza%' OR LOWER(pr.drug) LIKE '%saxenda%'
      OR LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%trulicity%'
      OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%byetta%' OR LOWER(pr.drug) LIKE '%bydureon%'
      OR LOWER(pr.drug) LIKE '%lixisenatide%' OR LOWER(pr.drug) LIKE '%adlyxin%'
    )
  GROUP BY
    fc.hadm_id
),

-- Step 5: Calculate aggregate statistics (counts and rates)
summary_stats AS (
  SELECT
    COUNT(hadm_id) AS total_patients,
    SUM(initiated_first_72h) AS patients_initiated_first_72h,
    SUM(initiated_final_24h) AS patients_initiated_final_24h,
    SAFE_DIVIDE(SUM(initiated_first_72h) * 100.0, COUNT(hadm_id)) AS initiation_rate_first_72h_pct,
    SAFE_DIVIDE(SUM(initiated_final_24h) * 100.0, COUNT(hadm_id)) AS initiation_rate_final_24h_pct
  FROM
    cohort_initiations
)

-- Step 6: Calculate absolute and relative change from the summary statistics
SELECT
  total_patients,
  patients_initiated_first_72h,
  patients_initiated_final_24h,
  ROUND(initiation_rate_first_72h_pct, 2) AS prevalence_and_initiation_rate_first_72h_pct,
  ROUND(initiation_rate_final_24h_pct, 2) AS prevalence_and_initiation_rate_final_24h_pct,
  ROUND(initiation_rate_final_24h_pct - initiation_rate_first_72h_pct, 2) AS absolute_change_pct_points,
  ROUND(SAFE_DIVIDE(initiation_rate_final_24h_pct - initiation_rate_first_72h_pct, initiation_rate_first_72h_pct) * 100, 2) AS relative_change_pct
FROM
  summary_stats;