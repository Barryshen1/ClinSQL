WITH
  -- Step 1: Identify all hospital admissions with a Heart Failure (HF) diagnosis
  -- and classify as 'Primary' or 'Secondary'.
  hf_admissions AS (
    SELECT
      dx.hadm_id,
      -- If the minimum sequence number for an HF diagnosis is 1, it's a primary diagnosis for that admission.
      CASE
        WHEN MIN(dx.seq_num) = 1 THEN 'Primary'
        ELSE 'Secondary'
      END AS hf_diagnosis_type
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
      LOWER(d_dx.long_title) LIKE '%heart failure%'
    GROUP BY
      dx.hadm_id
  ),

  -- Step 2: Count the number of CT or MRI procedures for each hospital admission.
  imaging_counts AS (
    SELECT
      proc.hadm_id,
      COUNT(*) AS num_scans
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
      ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
      -- Identify CT and MRI procedures by their description.
      LOWER(d_proc.long_title) LIKE '%computed tomography%'
      OR LOWER(d_proc.long_title) LIKE '%magnetic resonance imaging%'
    GROUP BY
      proc.hadm_id
  )

-- Step 3: Combine cohort, diagnosis, LOS, and procedure counts to generate the final report.
SELECT
  hf.hf_diagnosis_type,
  CASE
    WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_category,
  COUNT(DISTINCT adm.hadm_id) AS admission_count,
  AVG(COALESCE(img.num_scans, 0)) AS mean_mri_ct_per_admission
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
-- Join to filter for patient demographics.
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
-- Join to filter for only HF admissions and get the diagnosis type.
INNER JOIN
  hf_admissions AS hf
  ON adm.hadm_id = hf.hadm_id
-- Left join to include admissions that had no imaging scans.
LEFT JOIN
  imaging_counts AS img
  ON adm.hadm_id = img.hadm_id
WHERE
  -- Filter for the patient cohort: men aged 90-100.
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 90 AND 100
  -- Filter for the specified length of stay (LOS).
  AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
GROUP BY
  hf_diagnosis_type,
  los_category
ORDER BY
  hf_diagnosis_type,
  los_category;