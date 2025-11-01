WITH
-- Define the target population: males aged 75-85 with ischemic heart disease/ACS and COPD
target_population AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.hadm_id IN (
      -- Subquery to find admissions with ischemic heart disease/ACS (I20-I25, I21) and COPD (J44)
      SELECT
        di.hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON
        di.icd_code = d.icd_code
        AND di.icd_version = d.icd_version
      WHERE
        -- Ischemic heart disease/ACS (I20-I25, I21)
        (di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I23%' OR di.icd_code LIKE 'I24%' OR di.icd_code LIKE 'I25%')
        -- COPD (J44)
        OR (di.icd_code LIKE 'J44%')
      GROUP BY
        di.hadm_id
      HAVING
        -- Ensure both conditions are present (count distinct ICD codes)
        COUNT(DISTINCT CASE WHEN di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I23%' OR di.icd_code LIKE 'I24%' OR di.icd_code LIKE 'I25%' THEN di.icd_code END) > 0
        AND COUNT(DISTINCT CASE WHEN di.icd_code LIKE 'J44%' THEN di.icd_code END) > 0
    )
    AND a.dischtime IS NOT NULL  -- Ensure discharge time is recorded
)

-- Calculate the 75th percentile of hospital LOS for the target population
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER() AS percentile_75_los_days
FROM
  target_population
LIMIT 1;