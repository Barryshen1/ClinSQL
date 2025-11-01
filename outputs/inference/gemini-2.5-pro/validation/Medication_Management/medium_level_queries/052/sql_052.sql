WITH
-- Step 1: Find hospital admissions with both Type 2 Diabetes and Heart Failure diagnoses
DiagnosedHadms AS (
  SELECT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
  HAVING
    -- Check for at least one Type 2 Diabetes diagnosis code
    COUNTIF(
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250') OR
        (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'E11')
    ) > 0
    AND
    -- Check for at least one Heart Failure diagnosis code
    COUNTIF(
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428') OR
        (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50')
    ) > 0
),

-- Step 2: Define the final patient cohort based on demographics and stay length
Cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN DiagnosedHadms AS dh
    ON a.hadm_id = dh.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),

-- Step 3: Identify, categorize, and tag relevant diabetes medications by time window for the cohort
PatientMedsInWindow AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
        THEN 'First 48 Hours'
      WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
        THEN 'Final 24 Hours'
      ELSE NULL
    END AS time_window,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%'
        OR LOWER(pr.drug) LIKE '%glipizide%'
        OR LOWER(pr.drug) LIKE '%glyburide%'
        OR LOWER(pr.drug) LIKE '%glimepiride%'
        OR LOWER(pr.drug) LIKE '%pioglitazone%'
        OR LOWER(pr.drug) LIKE '%rosiglitazone%'
        OR LOWER(pr.drug) LIKE '%sitagliptin%'
        OR LOWER(pr.drug) LIKE '%acarbose%'
        OR LOWER(pr.drug) LIKE '%repaglinide%'
        OR LOWER(pr.drug) LIKE '%nateglinide%'
        OR LOWER(pr.drug) LIKE '%canagliflozin%'
        OR LOWER(pr.drug) LIKE '%dapagliflozin%'
        OR LOWER(pr.drug) LIKE '%empagliflozin%'
      THEN 'Oral'
      ELSE NULL
    END AS med_category
  FROM Cohort AS c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime IS NOT NULL
),

-- Step 4: Calculate total cohort size for percentage calculations
CohortSize AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_patients FROM Cohort
)

-- Final Step: Aggregate results by time window and calculate percentages
SELECT
  pm.time_window,
  -- Pct of patients in cohort receiving Insulin in the window
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN pm.med_category = 'Insulin' THEN pm.hadm_id END),
    cs.total_patients
  ) * 100 AS percentage_receiving_insulin,
  -- Pct of patients in cohort receiving Oral agents in the window
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN pm.med_category = 'Oral' THEN pm.hadm_id END),
    cs.total_patients
  ) * 100 AS percentage_receiving_oral_agents
FROM PatientMedsInWindow AS pm
CROSS JOIN CohortSize AS cs
WHERE
  pm.time_window IS NOT NULL
  AND pm.med_category IS NOT NULL
GROUP BY
  pm.time_window, cs.total_patients
ORDER BY
  pm.time_window DESC;