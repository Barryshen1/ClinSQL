WITH
  -- Step 1: Identify all hospital admissions for Heart Failure (HF) and determine if it was a primary diagnosis
  hf_admissions AS (
    SELECT
      dia.hadm_id,
      MIN(dia.seq_num) AS min_hf_seq_num
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dia
      ON dia.icd_code = d_dia.icd_code
      AND dia.icd_version = d_dia.icd_version
    WHERE
      LOWER(d_dia.long_title) LIKE '%heart failure%'
    GROUP BY
      dia.hadm_id
  ),

  -- Step 2: Count the number of CT or MRI scans for each hospital admission
  scan_counts AS (
    SELECT
      hadm_id,
      COUNT(*) AS num_scans
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE
      LOWER(short_description) LIKE '%ct %' OR LOWER(short_description) LIKE '%mri%'
    GROUP BY
      hadm_id
  ),

  -- Step 3: Create the base cohort of admissions meeting patient and stay criteria
  base_cohort AS (
    SELECT
      adm.hadm_id,
      -- Calculate age at the time of admission
      (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age AS age_at_admission,
      -- Calculate length of stay in days
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
      -- Filter for age at admission between 45 and 55
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 45 AND 55
  )

-- Final step: Join the cohorts, classify, group, and aggregate the results
SELECT
  CASE
    WHEN hf.min_hf_seq_num = 1
    THEN 'Primary'
    ELSE 'Secondary'
  END AS hf_diagnosis_type,
  CASE
    WHEN bc.los_days BETWEEN 1 AND 3
    THEN '1-3 days'
    WHEN bc.los_days BETWEEN 4 AND 7
    THEN '4-7 days'
  END AS los_group,
  AVG(COALESCE(sc.num_scans, 0)) AS mean_scans_per_admission,
  MIN(COALESCE(sc.num_scans, 0)) AS min_scans_per_admission,
  MAX(COALESCE(sc.num_scans, 0)) AS max_scans_per_admission
FROM
  base_cohort AS bc
-- Join with HF admissions to only include patients with a heart failure diagnosis
INNER JOIN
  hf_admissions AS hf
  ON bc.hadm_id = hf.hadm_id
-- Left join with scan counts to include admissions with zero scans
LEFT JOIN
  scan_counts AS sc
  ON bc.hadm_id = sc.hadm_id
GROUP BY
  hf_diagnosis_type,
  los_group
ORDER BY
  hf_diagnosis_type,
  los_group;