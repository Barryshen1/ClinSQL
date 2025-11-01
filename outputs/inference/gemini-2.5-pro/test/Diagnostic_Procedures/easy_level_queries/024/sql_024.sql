WITH
  -- Step 1: Define the cohort of hospital admissions for women aged 58-68
  cohort_admissions AS (
    SELECT
      adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 58 AND 68
  ),

  -- Step 2: Identify all relevant coronary angiography/PCI procedures from the entire database
  angio_pci_procedures AS (
    SELECT
      proc.hadm_id,
      proc.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
      ON proc.icd_code = d_proc.icd_code
      AND proc.icd_version = d_proc.icd_version
    WHERE
      LOWER(d_proc.long_title) LIKE '%coronary arteriograph%'
      OR LOWER(d_proc.long_title) LIKE '%percutaneous transluminal coronary angioplasty%'
      OR LOWER(d_proc.long_title) LIKE '%ptca%'
      OR LOWER(d_proc.long_title) LIKE '%coronary artery stent%'
      OR (LOWER(d_proc.long_title) LIKE '%dilation%' AND LOWER(d_proc.long_title) LIKE '%coronary artery%')
      OR LOWER(d_proc.long_title) LIKE '%percutaneous coronary intervention%'
  ),

  -- Step 3: Count the number of distinct procedures for each hospitalization in the cohort
  -- A LEFT JOIN is used to include hospitalizations with zero relevant procedures.
  proc_counts_per_admission AS (
    SELECT
      ca.hadm_id,
      COUNT(DISTINCT app.icd_code) AS num_distinct_procedures
    FROM cohort_admissions AS ca
    LEFT JOIN angio_pci_procedures AS app
      ON ca.hadm_id = app.hadm_id
    GROUP BY
      ca.hadm_id
  )

-- Step 4: Calculate the 75th percentile of the procedure counts
SELECT
  APPROX_QUANTILES(pcpa.num_distinct_procedures, 100)[OFFSET(75)] AS p75_distinct_procedures
FROM proc_counts_per_admission AS pcpa;