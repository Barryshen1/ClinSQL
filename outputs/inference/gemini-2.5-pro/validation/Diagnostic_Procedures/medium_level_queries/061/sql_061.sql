WITH
  -- Step 1: Identify admissions for female patients aged 64-74 with an AKI diagnosis
  aki_admissions AS (
    SELECT
      a.hadm_id,
      -- Calculate length of stay, rounding up to the nearest day
      CEIL(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS los_days,
      d.seq_num
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 64 AND 74
      -- Filter for ICD-9 and ICD-10 codes for Acute Kidney Injury/Failure
      AND (
        (d.icd_version = 9 AND d.icd_code LIKE '584%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
      )
  ),

  -- Step 2: Categorize admissions by LOS and classify AKI as Primary vs. Secondary
  categorized_admissions AS (
    SELECT
      hadm_id,
      CASE
        WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE NULL
      END AS los_category,
      -- If any AKI diagnosis has seq_num=1, it's primary for the admission
      CASE
        WHEN MIN(seq_num) = 1 THEN 'Primary'
        ELSE 'Secondary'
      END AS diagnosis_type
    FROM aki_admissions
    GROUP BY
      hadm_id,
      los_days
    HAVING
      los_days BETWEEN 1 AND 7
  ),

  -- Step 3: Count the number of imaging studies per admission from relevant sources
  imaging_counts AS (
    SELECT
      hadm_id,
      COUNT(*) AS num_imaging_studies
    FROM (
      -- ICD-9 (Diagnostic Radiology) and ICD-10 (Imaging) procedure codes
      SELECT
        hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
      WHERE
        (icd_version = 9 AND SUBSTR(icd_code, 1, 2) BETWEEN '87' AND '88')
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 1) = 'B')
      UNION ALL
      -- HCPCS/CPT codes for radiology
      SELECT
        hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
      WHERE
        hcpcs_cd BETWEEN '70000' AND '79999'
    ) AS all_imaging
    GROUP BY
      hadm_id
  ),

  -- Step 4: Join categorized admissions with imaging counts
  final_data AS (
    SELECT
      ca.los_category,
      ca.diagnosis_type,
      -- Admissions with no imaging will have a NULL count, so convert to 0
      COALESCE(ic.num_imaging_studies, 0) AS num_imaging_studies
    FROM categorized_admissions AS ca
    LEFT JOIN imaging_counts AS ic
      ON ca.hadm_id = ic.hadm_id
  )

-- Final Step: Calculate median and IQR for each stratum
SELECT
  los_category,
  diagnosis_type,
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(num_imaging_studies, 100)[OFFSET(50)] AS median_imaging_studies,
  (
    APPROX_QUANTILES(num_imaging_studies, 100)[OFFSET(75)]
    - APPROX_QUANTILES(num_imaging_studies, 100)[OFFSET(25)]
  ) AS iqr_imaging_studies
FROM final_data
GROUP BY
  los_category,
  diagnosis_type
ORDER BY
  los_category,
  diagnosis_type;