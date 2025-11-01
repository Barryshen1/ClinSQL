WITH
-- 1. Identify ACS admissions in 46-56 y/o females
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON d.subject_id = a.subject_id
      AND d.hadm_id = a.hadm_id
      AND d.seq_num = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON ddi.icd_code = d.icd_code
      AND ddi.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    -- ICD-10 codes for unstable angina and acute MI
    AND (
      d.icd_code = 'I20.0'
      OR STARTS_WITH(d.icd_code, 'I21')
      OR STARTS_WITH(d.icd_code, 'I22')
    )
),

-- 2. Identify hs-TnT itemids
hs_tnt_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin%'
    AND LOWER(label) LIKE '%hs%'
),

-- 3. First hs-TnT per admission
first_hs_tnt AS (
  SELECT
    la.subject_id,
    la.hadm_id,
    la.valuenum,
    la.charttime,
    ROW_NUMBER() OVER (PARTITION BY la.hadm_id ORDER BY la.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` la
    JOIN hs_tnt_items hsi
      ON la.itemid = hsi.itemid
    JOIN acs_admissions aa
      ON la.hadm_id = aa.hadm_id
      AND la.subject_id = aa.subject_id
  WHERE
    la.charttime BETWEEN aa.admittime AND aa.dischtime
    AND la.valuenum IS NOT NULL
)

SELECT
  CASE
    WHEN f.valuenum < 14 THEN 'Normal'
    WHEN f.valuenum BETWEEN 14 AND 52 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS hs_tnt_category,
  COUNT(1) AS count_admissions,
  ROUND(100.0 * COUNT(1) / SUM(COUNT(1)) OVER (), 1) AS pct_of_cohort,
  ROUND(AVG(
    TIMESTAMP_DIFF(aa.dischtime, aa.admittime, DAY)
  ), 1) AS mean_hospital_los_days
FROM
  first_hs_tnt f
  JOIN acs_admissions aa
    ON f.hadm_id = aa.hadm_id
    AND f.subject_id = aa.subject_id
WHERE
  f.rn = 1
GROUP BY
  hs_tnt_category
ORDER BY
  hs_tnt_category;