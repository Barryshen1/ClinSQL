with acute pancreatitis.
-- The results are stratified by length of stay (1-4 vs 5-8 days) and
-- whether the diagnosis was primary or secondary.

WITH
-- 1. Identify admissions with acute pancreatitis and classify as primary or secondary
ap_diagnoses AS (
  SELECT
    dia.hadm_id,
    CASE
      WHEN MIN(dia.seq_num) = 1
      THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON dia.icd_code = d.icd_code AND dia.icd_version = d.icd_version
  WHERE
    -- Find all variations of acute pancreatitis
    LOWER(d.long_title) LIKE '%acute pancreatitis%'
  GROUP BY
    dia.hadm_id
),

-- 2. Count the number of procedures per admission
proc_counts AS (
  SELECT
    hadm_id,
    COUNT(hadm_id) AS num_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY
    hadm_id
),

-- 3. Filter admissions for the specified patient cohort (age, gender) and bin by length of stay
patient_admissions AS (
  SELECT
    a.hadm_id,
    -- Bin the length of stay into the required groups
    CASE
      WHEN CEIL(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24) BETWEEN 1 AND 4
      THEN '1-4 days'
      WHEN CEIL(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24) BETWEEN 5 AND 8
      THEN '5-8 days'
      ELSE NULL
    END AS los_bin
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    -- Calculate age at admission and filter for 52-62 years old
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 52 AND 62
)

-- 4. Final aggregation: join the cohorts and calculate statistics
SELECT
  pa.los_bin,
  apd.diagnosis_type,
  AVG(COALESCE(pc.num_procedures, 0)) AS mean_procedures_per_admission,
  MIN(COALESCE(pc.num_procedures, 0)) AS min_procedures_per_admission,
  MAX(COALESCE(pc.num_procedures, 0)) AS max_procedures_per_admission
FROM
  patient_admissions AS pa
-- Join to include only admissions with acute pancreatitis
INNER JOIN
  ap_diagnoses AS apd
  ON pa.hadm_id = apd.hadm_id
-- Left join to include admissions with zero procedures
LEFT JOIN
  proc_counts AS pc
  ON pa.hadm_id = pc.hadm_id
WHERE
  -- Ensure we only consider admissions within the specified LOS bins
  pa.los_bin IS NOT NULL
GROUP BY
  pa.los_bin,
  apd.diagnosis_type
ORDER BY
  pa.los_bin,
  apd.diagnosis_type;