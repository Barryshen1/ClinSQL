WITH
  -- Step 1: Identify hospital admissions for male patients aged 75-85 with hepatic failure.
  hf_cohort_hadms AS (
    SELECT DISTINCT
      dx.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON a.hadm_id = dx.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
    WHERE
      p.gender = 'M'
      -- Calculate age at admission and filter for 75-85
      AND (
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year
      ) + p.anchor_age BETWEEN 75 AND 85
      -- Filter for diagnoses related to hepatic failure (using BigQuery compatible syntax)
      AND LOWER(d.long_title) LIKE '%hepatic failure%'
  ),
  -- Step 2: Get the ICU stay details for the cohort defined above.
  hf_cohort_stays AS (
    SELECT
      icu.stay_id,
      icu.hadm_id,
      icu.los,
      icu.intime
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      hf_cohort_hadms AS cohort
      ON icu.hadm_id = cohort.hadm_id
  ),
  -- Step 3: Calculate summary metrics (mortality, avg LOS, and instability score) for the cohort.
  final_cohort_metrics AS (
    WITH
      max_lactate_per_stay AS (
        SELECT
          cs.stay_id,
          MAX(le.valuenum) AS max_lactate
        FROM
          hf_cohort_stays AS cs
        INNER JOIN
          `physionet-data.mimiciv_3_1_hosp.labevents` AS le
          ON cs.hadm_id = le.hadm_id
        WHERE
          le.itemid = 50813 -- Lactate
          AND le.valuenum IS NOT NULL
          AND le.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
        GROUP BY
          cs.stay_id
      )
    SELECT
      AVG(adm.hospital_expire_flag) AS hepatic_failure_cohort_mortality,
      AVG(cs.los) AS hepatic_failure_cohort_avg_icu_los,
      MAX(ml.max_lactate) AS cohort_max_lactate_instability_score
    FROM
      hf_cohort_stays AS cs
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON cs.hadm_id = adm.hadm_id
    LEFT JOIN
      max_lactate_per_stay AS ml
      ON cs.stay_id = ml.stay_id
  ),
  -- Step 4: Define the itemids for the critical lab tests we want to analyze.
  critical_lab_itemids AS (
    SELECT
      itemid,
      label
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
      itemid IN (
        50885, -- Bilirubin, Total
        50862, -- Albumin
        50861, -- Alanine Aminotransferase (ALT)
        50878, -- Asparate Aminotransferase (AST)
        51237, -- INR(PT)
        50813, -- Lactate
        50912 -- Creatinine
      )
  ),
  -- Step 5: Calculate lab test frequencies for both cohorts within the first 48h of ICU stay. (Optimized)
  lab_freq_comparison AS (
    SELECT
      labs.label,
      -- Count tests and stays for the hepatic failure cohort
      COUNTIF(hf.stay_id IS NOT NULL) AS hf_lab_count,
      COUNT(DISTINCT hf.stay_id) AS hf_stay_count,
      -- Count tests and stays for the general ICU cohort
      COUNT(le.labevent_id) AS general_lab_count,
      COUNT(DISTINCT icu.stay_id) AS general_stay_count
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON icu.hadm_id = le.hadm_id
    INNER JOIN
      critical_lab_itemids AS labs
      ON le.itemid = labs.itemid
    LEFT JOIN
      hf_cohort_stays AS hf
      ON icu.stay_id = hf.stay_id
    WHERE
      -- Filter for labs charted within the first 48 hours of the ICU stay
      le.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
    GROUP BY
      labs.label
  )
-- Final Step: Combine the summary metrics and lab frequency comparison into a single output table.
SELECT
  lfc.label AS lab_test,
  SAFE_DIVIDE(lfc.hf_lab_count, lfc.hf_stay_count) AS hepatic_failure_cohort_avg_tests_per_stay,
  SAFE_DIVIDE(lfc.general_lab_count, lfc.general_stay_count) AS general_icu_cohort_avg_tests_per_stay,
  fcm.hepatic_failure_cohort_mortality,
  fcm.hepatic_failure_cohort_avg_icu_los,
  fcm.cohort_max_lactate_instability_score
FROM
  lab_freq_comparison AS lfc
CROSS JOIN
  final_cohort_metrics AS fcm
ORDER BY
  lfc.label;