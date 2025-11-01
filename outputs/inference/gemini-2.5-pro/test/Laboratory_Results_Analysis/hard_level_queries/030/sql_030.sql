WITH
  -- Step 1: Find all ICD codes related to "asthma with exacerbation"
  AsthmaDiagnoses AS (
    SELECT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
      LOWER(long_title) LIKE '%asthma%with%exacerbation%'
  ),
  -- Step 2: Identify the specific cohort of hospital admissions
  CohortAdmissions AS (
    SELECT DISTINCT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    INNER JOIN
      AsthmaDiagnoses AS adx
      ON dx.icd_code = adx.icd_code AND dx.icd_version = adx.icd_version
    WHERE
      pat.gender = 'F'
      AND (
        -- Calculate age at admission
        (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age
      ) BETWEEN 39 AND 49
  ),
  -- Step 3: Calculate the lab instability score for every admission with abnormal labs in the first 48h
  InstabilityScores AS (
    SELECT
      le.hadm_id,
      COUNT(*) AS lab_instability_score
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON le.hadm_id = adm.hadm_id
    WHERE
      le.flag = 'abnormal'
      -- Filter for labs within the first 48 hours of admission
      AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR)
    GROUP BY
      le.hadm_id
  ),
  -- Step 4: Calculate all required metrics for the specific cohort
  CohortAnalysis AS (
    SELECT
      APPROX_QUANTILES(COALESCE(scores.lab_instability_score, 0), 100)[OFFSET(75)] AS cohort_75th_percentile_instability_score,
      AVG(COALESCE(scores.lab_instability_score, 0)) AS cohort_avg_instability_score,
      AVG(DATETIME_DIFF(ca.dischtime, ca.admittime, DAY)) AS cohort_avg_los_days,
      AVG(CAST(ca.hospital_expire_flag AS FLOAT64)) * 100 AS cohort_in_hospital_mortality_percent
    FROM
      CohortAdmissions AS ca
    LEFT JOIN
      InstabilityScores AS scores
      ON ca.hadm_id = scores.hadm_id
  ),
  -- Step 5: Calculate the average instability score for the comparison group (all inpatients)
  AllInpatientAnalysis AS (
    SELECT
      AVG(COALESCE(scores.lab_instability_score, 0)) AS all_inpatients_avg_instability_score
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    LEFT JOIN
      InstabilityScores AS scores
      ON adm.hadm_id = scores.hadm_id
  )
-- Final Step: Combine cohort and baseline results into a single output table
SELECT
  cohort.cohort_75th_percentile_instability_score,
  cohort.cohort_avg_instability_score,
  all_patients.all_inpatients_avg_instability_score,
  cohort.cohort_avg_los_days,
  cohort.cohort_in_hospital_mortality_percent
FROM
  CohortAnalysis AS cohort,
  AllInpatientAnalysis AS all_patients;