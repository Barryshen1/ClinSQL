WITH
  -- Step 1: Find all hospital admissions with diagnoses for both neutropenia and fever
  neutropenic_fever_admissions AS (
    SELECT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
    HAVING
      -- Condition for neutropenia
      (
        MAX(
          CASE
            WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) = '2880' THEN 1
            ELSE 0
          END
        ) = 1
        OR MAX(
          CASE
            WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'D70' THEN 1
            ELSE 0
          END
        ) = 1
      )
      AND
      -- Condition for fever
      (
        MAX(
          CASE
            WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) = '7806' THEN 1
            ELSE 0
          END
        ) = 1
        OR MAX(
          CASE
            WHEN icd_version = 10 AND icd_code IN ('R509', 'R5081') THEN 1
            ELSE 0
          END
        ) = 1
      )
  ),
  -- Step 2: Define the base cohort of female patients aged 40-50 with neutropenic fever
  cohort_admissions AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN neutropenic_fever_admissions AS nfa
      ON adm.hadm_id = nfa.hadm_id
    WHERE
      pat.gender = 'F'
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 40 AND 50
  ),
  -- Step 3: Calculate medication complexity score (distinct meds in first 48h) for the cohort
  med_complexity AS (
    SELECT
      c.hadm_id,
      COUNT(DISTINCT e.medication) AS med_score
    FROM cohort_admissions AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
      ON c.hadm_id = e.hadm_id
    WHERE
      e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    GROUP BY
      c.hadm_id
  ),
  -- Step 4: Determine 30-day readmissions for all patients
  readmission_info AS (
    SELECT
      hadm_id,
      dischtime,
      LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  readmission_flag AS (
    SELECT
      hadm_id,
      CASE
        WHEN DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
        ELSE 0
      END AS readmitted_30_days
    FROM readmission_info
  ),
  -- Step 5: Combine all metrics for the cohort and assign quartiles
  combined_data AS (
    SELECT
      c.hadm_id,
      COALESCE(mc.med_score, 0) AS med_score,
      DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
      c.hospital_expire_flag,
      COALESCE(rf.readmitted_30_days, 0) AS readmitted_30_days,
      NTILE(4) OVER (
        ORDER BY
          COALESCE(mc.med_score, 0)
      ) AS quartile
    FROM cohort_admissions AS c
    LEFT JOIN med_complexity AS mc
      ON c.hadm_id = mc.hadm_id
    LEFT JOIN readmission_flag AS rf
      ON c.hadm_id = rf.hadm_id
  )
-- Step 6: Final aggregation by quartile
SELECT
  quartile,
  COUNT(hadm_id) AS admission_count,
  ROUND(AVG(med_score), 2) AS mean_med_score,
  MIN(med_score) AS min_med_score,
  MAX(med_score) AS max_med_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent,
  ROUND(AVG(readmitted_30_days) * 100, 2) AS readmission_30_day_percent
FROM combined_data
GROUP BY
  quartile
ORDER BY
  quartile;