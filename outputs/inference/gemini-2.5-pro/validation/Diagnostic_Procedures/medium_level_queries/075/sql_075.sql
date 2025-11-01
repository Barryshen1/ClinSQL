WITH
  -- Step 1: Identify admissions for male patients aged 59-69 with a hospital stay of 1-7 days.
  base_admissions AS (
    SELECT
      p.subject_id,
      adm.hadm_id,
      DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON p.subject_id = adm.subject_id
    WHERE
      p.gender = 'M'
      AND (
        EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age
      ) BETWEEN 59 AND 69
      AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
  ),
  -- Step 2: Filter the above admissions for those with an Acute Coronary Syndrome (ACS) diagnosis.
  acs_admissions_with_seq AS (
    SELECT
      b.hadm_id,
      b.los_days,
      dx.seq_num
    FROM
      base_admissions AS b
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON b.hadm_id = dx.hadm_id
    WHERE
      -- ICD-9 codes for ACS (AMI, Unstable Angina)
      (
        dx.icd_version = 9
        AND (
          STARTS_WITH(dx.icd_code, '410') -- Acute Myocardial Infarction
          OR dx.icd_code = '4111' -- Intermediate coronary syndrome
        )
      )
      -- ICD-10 codes for ACS (AMI, Unstable Angina, etc.)
      OR (
        dx.icd_version = 10
        AND (
          dx.icd_code = 'I200' -- Unstable angina
          OR STARTS_WITH(dx.icd_code, 'I21') -- Acute myocardial infarction
          OR STARTS_WITH(dx.icd_code, 'I22') -- Subsequent ST elevation (STEMI) and non-ST elevation (NSTEMI) myocardial infarction
          OR dx.icd_code IN ('I240', 'I248', 'I249') -- Other acute ischemic heart diseases
        )
      )
  ),
  -- Step 3: For each admission, determine if ACS was a primary diagnosis (min seq_num = 1)
  stratified_admissions AS (
    SELECT
      hadm_id,
      los_days,
      MIN(seq_num) AS min_acs_seq_num
    FROM
      acs_admissions_with_seq
    GROUP BY
      hadm_id,
      los_days
  ),
  -- Step 4: Count the number of procedures for each admission.
  proc_counts AS (
    SELECT
      hadm_id,
      COUNT(seq_num) AS num_procedures
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY
      hadm_id
  ),
  -- Step 5: Combine all data, creating the final stratification columns and handling cases with zero procedures.
  final_data AS (
    SELECT
      s.hadm_id,
      COALESCE(p.num_procedures, 0) AS num_procedures,
      CASE
        WHEN s.los_days BETWEEN 1 AND 3
        THEN '1-3 days'
        ELSE '4-7 days'
      END AS los_category,
      CASE
        WHEN s.min_acs_seq_num = 1
        THEN 'Primary'
        ELSE 'Secondary'
      END AS diagnosis_category
    FROM
      stratified_admissions AS s
    LEFT JOIN
      proc_counts AS p
      ON s.hadm_id = p.hadm_id
  )
-- Step 6: Final aggregation to calculate percentiles for each stratum.
SELECT
  los_category,
  diagnosis_category,
  COUNT(hadm_id) AS num_admissions,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS p25_procedures,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS p50_procedures,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75_procedures
FROM
  final_data
GROUP BY
  los_category,
  diagnosis_category
ORDER BY
  los_category,
  diagnosis_category;