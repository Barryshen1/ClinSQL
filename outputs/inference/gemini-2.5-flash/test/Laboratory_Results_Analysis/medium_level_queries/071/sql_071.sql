WITH
  -- CTE 1: Identify eligible admissions: female patients aged 43-53 with suspected ACS diagnoses
  suspected_acs_admissions AS (
    SELECT DISTINCT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 43 AND 53
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        WHERE
          di.hadm_id = adm.hadm_id
          AND (
            -- ICD-9 codes for Acute MI (410) and other ischemic heart disease/unstable angina (411)
            (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%'))
            -- ICD-10 codes for Acute MI (I21) and Unstable angina (I200)
            OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code = 'I200'))
          )
      )
  ),
  -- CTE 2: Get the initial Troponin T measurement for each relevant admission
  initial_troponin_t AS (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.valuenum AS initial_troponin_t_value,
      le.charttime
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    WHERE
      le.itemid = 50980 -- itemid for 'Troponin T' in MIMIC-IV
      AND le.valuenum IS NOT NULL
      AND le.valuenum >= 0 -- Filter out potentially erroneous negative values
    QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
  ),
  -- CTE 3: Combine admission data with initial Troponin T and categorize it
  categorized_admissions AS (
    SELECT
      ac.subject_id,
      ac.hadm_id,
      DATETIME_DIFF(ac.dischtime, ac.admittime, DAY) AS los_hospital,
      CASE
        WHEN it.initial_troponin_t_value < 0.01 THEN 'Normal'
        WHEN it.initial_troponin_t_value >= 0.01 AND it.initial_troponin_t_value < 0.03 THEN 'Borderline'
        WHEN it.initial_troponin_t_value >= 0.03 THEN 'Elevated'
        ELSE 'Unknown' -- Should ideally not be reached given previous filters
      END AS troponin_category
    FROM
      suspected_acs_admissions AS ac
    INNER JOIN
      initial_troponin_t AS it
      ON ac.subject_id = it.subject_id AND ac.hadm_id = it.hadm_id
    WHERE
      it.initial_troponin_t_value IS NOT NULL -- Ensure only admissions with a valid initial Troponin T are included
  )
-- Final aggregation to calculate counts, percentages, and average hospital LOS
SELECT
  ca.troponin_category,
  COUNT(ca.hadm_id) AS count_admissions, -- Counting admissions, not distinct patients
  ROUND(COUNT(ca.hadm_id) * 100.0 / SUM(COUNT(ca.hadm_id)) OVER (), 2) AS percentage_of_admissions,
  ROUND(AVG(ca.los_hospital), 2) AS average_hospital_los_days
FROM
  categorized_admissions AS ca
WHERE
  ca.troponin_category != 'Unknown' -- Exclude any cases not falling into defined categories
GROUP BY
  ca.troponin_category
ORDER BY
  CASE ca.troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;