WITH
  -- Step 1: Create a base cohort of female patients aged 78-88 with a hospital stay of 1-8 days.
  patient_admissions AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      CASE
        WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 4
          THEN '1-4 days'
        WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 5 AND 8
          THEN '5-8 days'
      END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 78 AND 88
      AND a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
      AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 8
  ),

  -- Step 2: Filter the base cohort for admissions with a DVT diagnosis.
  dvt_admissions AS (
    SELECT DISTINCT
      pa.hadm_id,
      pa.los_group
    FROM patient_admissions AS pa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON pa.hadm_id = d.hadm_id
    WHERE
      -- ICD-9 codes for DVT (phlebitis/thrombosis of deep vessels of lower extremities)
      (d.icd_version = 9 AND (d.icd_code LIKE '4511%' OR d.icd_code LIKE '4534%'))
      -- ICD-10 codes for DVT (phlebitis/thrombosis of deep veins of lower extremities)
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I801%' OR d.icd_code LIKE 'I802%' OR d.icd_code LIKE 'I824%'))
  ),

  -- Step 3: Count relevant noninvasive diagnostic procedures (ultrasounds/duplex scans) per admission.
  diagnostic_counts AS (
    SELECT
      hadm_id,
      COUNT(*) AS num_diagnostics
    FROM (
      -- ICD-9-CM procedure code for peripheral vascular ultrasound
      SELECT
        hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
      WHERE
        icd_code = '8877' AND icd_version = 9
      UNION ALL
      -- HCPCS codes for duplex scan of extremity veins
      SELECT
        hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
      WHERE
        hcpcs_cd IN ('93970', '93971')
    ) AS diagnostics
    GROUP BY
      hadm_id
  ),

  -- Step 4: Identify all hospital admissions that included an ICU stay.
  icu_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )

-- Step 5: Combine the data and calculate final metrics.
SELECT
  dvt.los_group,
  CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status,
  COUNT(dvt.hadm_id) AS admission_count,
  AVG(COALESCE(dc.num_diagnostics, 0)) AS mean_noninvasive_diagnostics
FROM dvt_admissions AS dvt
LEFT JOIN icu_admissions AS icu
  ON dvt.hadm_id = icu.hadm_id
LEFT JOIN diagnostic_counts AS dc
  ON dvt.hadm_id = dc.hadm_id
GROUP BY
  los_group,
  icu_status
ORDER BY
  los_group,
  icu_status;