WITH aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%')  -- acute renal failure (ICD-9)
      OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%') -- acute kidney failure (ICD-10)
    )
),
aki_with_icu AS (
  SELECT
    c.*,
    CASE WHEN i.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_flag
  FROM aki_admissions c
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i
  ON c.hadm_id = i.hadm_id
),
diag_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY hadm_id
),
micro_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS micro_count
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents`
  GROUP BY hadm_id
),
aki_with_counts AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_group,
    a.icu_flag,
    COALESCE(l.lab_count,0) + COALESCE(m.micro_count,0) AS total_noninvasive_tests
  FROM aki_with_icu a
  LEFT JOIN diag_counts l ON a.hadm_id = l.hadm_id
  LEFT JOIN micro_counts m ON a.hadm_id = m.hadm_id
)
SELECT
  los_group,
  icu_flag,
  AVG(total_noninvasive_tests) AS mean_tests,
  MIN(total_noninvasive_tests) AS min_tests,
  MAX(total_noninvasive_tests) AS max_tests
FROM aki_with_counts
GROUP BY los_group, icu_flag
ORDER BY los_group, icu_flag;