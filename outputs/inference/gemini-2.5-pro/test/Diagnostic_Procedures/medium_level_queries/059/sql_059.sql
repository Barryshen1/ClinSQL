WITH
-- Step 1: Define the cohort of male patients (67-77yo) with a heart failure diagnosis,
-- and classify the HF as primary or secondary.
hf_admissions AS (
  SELECT
    a.hadm_id,
    CEIL(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS los_days,
    -- If any 'heart failure' diagnosis has seq_num = 1, it's primary.
    MAX(
      CASE
        WHEN
          LOWER(diag.long_title) LIKE '%heart failure%' AND dx.seq_num = 1
          THEN 1
        ELSE 0
      END
    ) AS is_primary_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    -- Inner join ensures we only consider admissions with an HF diagnosis.
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS diag
    ON dx.icd_code = diag.icd_code AND dx.icd_version = diag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND LOWER(diag.long_title) LIKE '%heart failure%'
  GROUP BY
    a.hadm_id,
    a.admittime,
    a.dischtime
),

-- Step 2: Count the number of imaging studies per admission.
-- Imaging studies are identified from both ICD and HCPCS procedure codes.
imaging_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_imaging
  FROM
    (
      -- From ICD-coded procedures
      SELECT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
      WHERE
        LOWER(d_proc.long_title) LIKE '%tomography%' -- CT
        OR LOWER(d_proc.long_title) LIKE '%magnetic resonance imaging%' -- MRI
        OR LOWER(d_proc.long_title) LIKE '%x-ray%'
        OR LOWER(d_proc.long_title) LIKE '%radiography%'
        OR LOWER(d_proc.long_title) LIKE '%fluoroscopy%'
        OR LOWER(d_proc.long_title) LIKE '%ultrasound%'
        OR LOWER(d_proc.long_title) LIKE '%echocardiogra%'
        OR LOWER(d_proc.long_title) LIKE '%angiogra%'
      UNION ALL
      -- From HCPCS-coded procedures (Radiology section 7xxxx)
      SELECT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
      WHERE
        SUBSTR(hcpcs_cd, 1, 1) = '7'
    ) AS all_imaging
  GROUP BY
    hadm_id
),

-- Step 3: Combine cohort, LOS, and imaging data for final analysis.
analysis_data AS (
  SELECT
    hf.hadm_id,
    COALESCE(img.num_imaging, 0) AS num_imaging,
    -- Create LOS category
    CASE
      WHEN hf.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN hf.los_days BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_group,
    -- Create HF type category
    CASE
      WHEN hf.is_primary_hf = 1 THEN 'Primary HF'
      ELSE 'Secondary HF'
    END AS hf_type
  FROM
    hf_admissions AS hf
  LEFT JOIN
    imaging_counts AS img
    ON hf.hadm_id = img.hadm_id
)

-- Step 4: Group by the defined categories and calculate percentiles.
SELECT
  los_group,
  hf_type,
  COUNT(hadm_id) AS num_admissions,
  APPROX_QUANTILES(num_imaging, 100)[OFFSET(25)] AS p25_imaging_studies,
  APPROX_QUANTILES(num_imaging, 100)[OFFSET(50)] AS p50_imaging_studies,
  APPROX_QUANTILES(num_imaging, 100)[OFFSET(75)] AS p75_imaging_studies
FROM
  analysis_data
WHERE
  los_group IS NOT NULL -- Fiter for only the LOS groups of interest
GROUP BY
  los_group,
  hf_type
ORDER BY
  los_group,
  hf_type;