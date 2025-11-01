WITH
  -- Step 1: Identify all admissions for female patients aged 53-63 with a 1-8 day stay
  cohort_admissions AS (
    SELECT
      a.hadm_id,
      a.dischtime,
      a.admittime,
      -- Calculate age at admission
      (
        EXTRACT(
          YEAR
          FROM a.admittime
        ) - p.anchor_year
      ) + p.anchor_age AS age_at_admission,
      -- Calculate length of stay in days
      DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'F'
      AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
      AND (
        (
          EXTRACT(
            YEAR
            FROM a.admittime
          ) - p.anchor_year
        ) + p.anchor_age
      ) BETWEEN 53 AND 63
  ),
  -- Step 2: Filter the cohort for admissions with an Upper GI Bleed diagnosis
  ugib_cohort AS (
    SELECT DISTINCT
      c.hadm_id,
      c.los_days
    FROM cohort_admissions AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON c.hadm_id = d.hadm_id
    WHERE
      d.icd_code IN (
        -- ICD-9 codes for UGIB
        '53100', '53120', '53140', '53160', '53200', '53220', '53240',
        '53260', '53300', '53320', '53340', '53360', '53400', '53420',
        '53440', '53460', '5780', '5781', '5789',
        -- ICD-10 codes for UGIB
        'K250', 'K251', 'K252', 'K254', 'K255', 'K256', 'K260', 'K261',
        'K262', 'K264', 'K265', 'K266', 'K270', 'K271', 'K272', 'K274',
        'K275', 'K276', 'K280', 'K281', 'K282', 'K284', 'K285', 'K286',
        'K920', 'K921', 'K922'
      )
  ),
  -- Step 3: Count procedures for each admission in the UGIB cohort.
  -- Use a LEFT JOIN to include admissions with zero procedures.
  admission_proc_counts AS (
    SELECT
      ugib.hadm_id,
      ugib.los_days,
      COUNT(proc.icd_code) AS num_procedures
    FROM ugib_cohort AS ugib
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON ugib.hadm_id = proc.hadm_id
    GROUP BY
      ugib.hadm_id,
      ugib.los_days
  )
-- Final Step: Stratify by LOS and calculate p25, p50, p75 of procedure counts
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8
    THEN '5-8 days'
  END AS los_category,
  APPROX_QUANTILES(num_procedures, 100) [
OFFSET
  (25)] AS p25_procedures,
  APPROX_QUANTILES(num_procedures, 100) [
OFFSET
  (50)] AS p50_procedures,
  APPROX_QUANTILES(num_procedures, 100) [
OFFSET
  (75)] AS p75_procedures
FROM admission_proc_counts
GROUP BY
  los_category
ORDER BY
  los_category;