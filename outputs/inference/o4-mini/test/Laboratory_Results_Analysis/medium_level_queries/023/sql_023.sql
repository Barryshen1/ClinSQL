WITH acs_admissions AS (
  -- Identify ACS admissions for female patients aged 67-77
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    -- ICD-9 for acute MI (410.*) or unstable angina (411.1)
    AND (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^410'))
      OR (d.icd_version = 9 AND d.icd_code = '4111')
    )
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
),
troponin_items AS (
  -- Troponin T itemids from lab catalog
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  -- Get first troponin measurement per admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value
  FROM (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.valuenum,
      le.charttime,
      ROW_NUMBER() OVER (
        PARTITION BY le.hadm_id
        ORDER BY le.charttime
      ) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` le
      JOIN troponin_items ti
        ON le.itemid = ti.itemid
    WHERE
      le.valuenum IS NOT NULL
  ) le
  WHERE le.rn = 1
),
cohort AS (
  -- Combine ACS admissions with first troponin values
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    ft.troponin_value,
    CASE
      WHEN ft.troponin_value <= 0.04 THEN 'normal'
      WHEN ft.troponin_value > 0.04 AND ft.troponin_value <= 0.1 THEN 'borderline'
      WHEN ft.troponin_value > 0.1 THEN 'elevated'
    END AS troponin_category
  FROM
    acs_admissions a
    JOIN first_troponin ft
      ON a.hadm_id = ft.hadm_id
),
totals AS (
  -- Total number of ACS admissions in cohort
  SELECT COUNT(*) AS total_admissions
  FROM cohort
)
-- Final aggregation by troponin category
SELECT
  c.troponin_category,
  COUNT(*) AS admissions_count,
  ROUND( COUNT(*) / t.total_admissions * 100, 1 ) AS percent_of_admissions,
  ROUND( SUM(c.hospital_expire_flag) / COUNT(*) * 100, 1 ) AS in_hospital_mortality_rate
FROM
  cohort c,
  totals t
GROUP BY
  c.troponin_category,
  t.total_admissions
ORDER BY
  troponin_category;