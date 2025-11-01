WITH
  -- Step 1: Identify the cohort of female patients aged 70-80 admitted for lower GI bleeding.
  cohort_base AS (
    SELECT DISTINCT -- Use DISTINCT to ensure one row per admission, even with multiple matching primary diagnoses.
      pat.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      pat.dod
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON pat.subject_id = adm.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'F'
      -- Calculate and filter by age at admission
      AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 70 AND 80
      -- Filter for primary diagnosis of lower GI bleeding
      AND dx.seq_num = 1
      AND (
        (dx.icd_version = 9 AND dx.icd_code IN ('5781', '5693'))
        OR (dx.icd_version = 10 AND dx.icd_code IN ('K921', 'K922', 'K625'))
      )
  ),
  -- Step 2: Define and calculate the complication-based risk score for each admission.
  complication_score AS (
    SELECT
      hadm_id,
      COUNT(DISTINCT complication_type) AS risk_score
    FROM (
      SELECT
        hadm_id,
        CASE
          -- Sepsis
          WHEN
            (icd_version = 9 AND icd_code IN ('99591', '78552'))
            OR (icd_version = 10 AND (icd_code = 'A419' OR SUBSTR(icd_code, 1, 4) = 'R652'))
            THEN 'Sepsis'
          -- Acute Kidney Injury
          WHEN
            (icd_version = 9 AND icd_code = '5849')
            OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'N17')
            THEN 'AKI'
          -- Acute Myocardial Infarction
          WHEN
            (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
            OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22'))
            THEN 'AMI'
          -- Stroke
          WHEN
            (icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '434' OR icd_code = '436'))
            OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I64')
            THEN 'Stroke'
          -- Respiratory Failure
          WHEN
            (icd_version = 9 AND icd_code IN ('51881', '51884', '7991'))
            OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'J96')
            THEN 'Respiratory Failure'
          ELSE NULL
        END AS complication_type
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        -- Only consider secondary diagnoses as complications
        seq_num > 1
    ) AS complication_list
    WHERE
      complication_type IS NOT NULL
    GROUP BY
      hadm_id
  ),
  -- Step 3: Combine cohort with scores, calculate metrics per admission, and assign quintiles.
  analysis_data AS (
    SELECT
      cb.hadm_id,
      -- Assign quintile based on the risk score (0 for those with no complications)
      NTILE(5) OVER (ORDER BY COALESCE(cs.risk_score, 0)) AS risk_quintile,
      -- Flag for 90-day mortality
      (cb.dod IS NOT NULL AND cb.dod <= DATETIME_ADD(cb.admittime, INTERVAL 90 DAY)) AS mortality_90day,
      -- Flag for having any major complication
      (COALESCE(cs.risk_score, 0) > 0) AS has_major_complication,
      -- Calculate length of stay in days
      DATETIME_DIFF(cb.dischtime, cb.admittime, DAY) AS los_days
    FROM
      cohort_base AS cb
      LEFT JOIN complication_score AS cs ON cb.hadm_id = cs.hadm_id
  )
-- Step 4: Final aggregation to report metrics per quintile.
SELECT
  risk_quintile,
  COUNT(hadm_id) AS N,
  -- Calculate 90-day mortality rate as a percentage
  ROUND(AVG(IF(mortality_90day, 1.0, 0.0)) * 100, 2) AS mortality_90day_rate,
  -- Calculate major complication rate as a percentage
  ROUND(AVG(IF(has_major_complication, 1.0, 0.0)) * 100, 2) AS major_complication_rate,
  -- Calculate median LOS for 90-day survivors
  ROUND(
    APPROX_QUANTILES(
      IF(
        NOT mortality_90day AND los_days IS NOT NULL, los_days, NULL
      ), 100
    )[OFFSET(50)], 1
  ) AS median_los_survivors
FROM
  analysis_data
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;