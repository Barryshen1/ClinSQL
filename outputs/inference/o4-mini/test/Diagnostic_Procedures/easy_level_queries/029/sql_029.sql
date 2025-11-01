WITH
-- 1. Define the patient cohort: male patients aged 78 to 88
patient_cohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),

-- 2. Identify all pacemaker/ICD procedure codes
pm_icd_codes AS (
  SELECT
    ip.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS ip
  WHERE
    LOWER(ip.long_title) LIKE '%pacemaker%'
    OR LOWER(ip.long_title) LIKE '%cardioverter%'
    OR LOWER(ip.long_title) LIKE '%icd%'
  GROUP BY
    ip.icd_code
),

-- 3. Extract all patient procedures that match our pacemaker/ICD code list
patient_pm_procs AS (
  SELECT
    pr.subject_id,
    pr.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
  JOIN
    pm_icd_codes AS pc
  ON
    pr.icd_code = pc.icd_code
  WHERE
    pr.icd_version IN (9, 10)  -- include both ICD-9 and ICD-10 if present
),

-- 4. Count distinct pacemaker/ICD procedures per patient
patient_proc_counts AS (
  SELECT
    c.subject_id,
    COUNT(DISTINCT pp.icd_code) AS proc_count
  FROM
    patient_cohort AS c
  LEFT JOIN
    patient_pm_procs AS pp
  ON
    c.subject_id = pp.subject_id
  GROUP BY
    c.subject_id
)

-- 5. Compute the 25th percentile of the distribution of proc_count
SELECT
  -- APPROX_QUANTILES returns an array of quantiles; we take the 25th percentile (index 25 of 0..100)
  APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS percentile_25_proc_count
FROM
  patient_proc_counts;