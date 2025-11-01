WITH
  -- Step 1 & 2: Identify the cohort of female patients, aged 47-57,
  -- hospitalized for acute pancreatitis, with a LOS between 1 and 8 days.
  pancreatitis_admissions AS (
    SELECT DISTINCT
      p.subject_id,
      a.hadm_id,
      -- Calculate length of stay in days
      DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    WHERE
      -- Filter for women
      p.gender = 'F'
      -- Filter for age at admission between 47 and 57
      AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 47 AND 57
      -- Filter for acute pancreatitis using ICD-9 ('5770') and ICD-10 ('K85%') codes
      AND (d.icd_code = '5770' OR d.icd_code LIKE 'K85%')
      -- Pre-filter for the total LOS range of interest
      AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
  ),

  -- Step 3: Count CT or MRI procedures for each hospital admission.
  imaging_procedures AS (
    SELECT
      h.hadm_id,
      COUNT(*) AS num_procedures
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d
      ON h.hcpcs_cd = d.code
    WHERE
      -- Use a regular expression to find procedures containing CT or MRI keywords
      REGEXP_CONTAINS(LOWER(d.long_description), r'ct |mri|computed tomography|magnetic resonance')
    GROUP BY
      h.hadm_id
  )

-- Step 4: Combine the cohort with procedure counts and aggregate by LOS category.
SELECT
  CASE
    WHEN pa.los_days BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN pa.los_days BETWEEN 5 AND 8
    THEN '5-8 days'
  END AS los_category,
  COUNT(DISTINCT pa.subject_id) AS patient_count,
  COUNT(DISTINCT pa.hadm_id) AS admission_count,
  AVG(COALESCE(ip.num_procedures, 0)) AS mean_ct_mri_procedures_per_admission
FROM
  pancreatitis_admissions AS pa
LEFT JOIN
  imaging_procedures AS ip
  ON pa.hadm_id = ip.hadm_id
GROUP BY
  los_category
ORDER BY
  los_category;