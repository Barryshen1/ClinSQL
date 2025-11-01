WITH
  -- Step 1: Identify male patients aged 51-61
  patient_cohort AS (
    SELECT
      p.subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 51 AND 61
  ),

  -- Step 2: Get all ICU stays for this patient cohort
  icu_stays_cohort AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      patient_cohort AS pc
      ON icu.subject_id = pc.subject_id
  ),

  -- Step 3: Calculate average SpO2 for the first 48 hours of each ICU stay
  first_48hr_avg_spo2 AS (
    SELECT
      ce.stay_id,
      AVG(ce.valuenum) AS avg_spo2
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN
      icu_stays_cohort AS isc
      ON ce.stay_id = isc.stay_id
    WHERE
      ce.itemid = 220277 -- SpO2 from pulse oximeter
      AND ce.valuenum > 0
      AND ce.valuenum <= 100 -- Data cleaning for plausible values
      AND ce.charttime BETWEEN isc.intime AND DATETIME_ADD(isc.intime, INTERVAL 48 HOUR)
    GROUP BY
      ce.stay_id
  ),

  -- Step 4: Identify hospital admissions with an AKI diagnosis
  aki_admissions AS (
    SELECT DISTINCT
      diag.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    WHERE
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%') -- ICD-9 for Acute kidney failure
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%') -- ICD-10 for Acute kidney injury
  )

-- Step 5: Combine, categorize, and report results
SELECT
  CASE
    WHEN spo2.avg_spo2 < 90 THEN '<90'
    WHEN spo2.avg_spo2 >= 90 AND spo2.avg_spo2 <= 92 THEN '90-92'
    WHEN spo2.avg_spo2 > 92 AND spo2.avg_spo2 <= 95 THEN '93-95'
    WHEN spo2.avg_spo2 > 95 THEN '>95'
  END AS first_48hr_avg_spo2_category,
  COUNT(DISTINCT isc.stay_id) AS number_of_icu_stays,
  AVG(CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100 AS aki_rate_percent
FROM
  first_48hr_avg_spo2 AS spo2
INNER JOIN
  icu_stays_cohort AS isc
  ON spo2.stay_id = isc.stay_id
LEFT JOIN
  aki_admissions AS aki
  ON isc.hadm_id = aki.hadm_id
GROUP BY
  first_48hr_avg_spo2_category
ORDER BY
  CASE
    WHEN first_48hr_avg_spo2_category = '<90' THEN 1
    WHEN first_48hr_avg_spo2_category = '90-92' THEN 2
    WHEN first_48hr_avg_spo2_category = '93-95' THEN 3
    WHEN first_48hr_avg_spo2_category = '>95' THEN 4
  END;