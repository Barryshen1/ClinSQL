WITH acs_icd_codes AS (
  -- ICD-10: I21 (AMI), I22 (AMI), I20.0 (unstable angina)
  -- ICD-9: 410 (AMI), 411.1 (unstable angina)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I21') OR
      REGEXP_CONTAINS(icd_code, r'^I22') OR
      icd_code = 'I20.0'
    ))
    OR
    (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^410') OR
      icd_code = '4111'
    ))
),
acs_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN acs_icd_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
),
male_aged_79_89 AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 79 AND 89
),
troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
initial_troponin AS (
  -- Get first Troponin T per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN troponin_t_items t
    ON l.itemid = t.itemid
  WHERE l.valuenum IS NOT NULL
),
cohort AS (
  -- Join all filters: ACS, male, age, initial Troponin T
  SELECT
    a.subject_id,
    a.hadm_id,
    i.charttime,
    i.valuenum AS troponin_t,
    i.valueuom
  FROM acs_admissions a
  INNER JOIN male_aged_79_89 m
    ON a.subject_id = m.subject_id
  INNER JOIN initial_troponin i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE i.rn = 1
    AND (i.valueuom IS NULL OR LOWER(i.valueuom) IN ('ng/ml', 'ng/ml.'))
    AND i.valuenum IS NOT NULL
),
categorized AS (
  SELECT
    *,
    CASE
      WHEN troponin_t < 0.01 THEN 'Normal'
      WHEN troponin_t >= 0.01 AND troponin_t <= 0.03 THEN 'Borderline'
      WHEN troponin_t > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM cohort
)
SELECT
  troponin_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(troponin_t), 4) AS mean_troponin_t,
  ROUND(APPROX_QUANTILES(troponin_t, 2)[OFFSET(1)], 4) AS median_troponin_t,
  ROUND(APPROX_QUANTILES(troponin_t, 4)[OFFSET(1)], 4) AS troponin_t_25th_percentile,
  ROUND(APPROX_QUANTILES(troponin_t, 4)[OFFSET(3)], 4) AS troponin_t_75th_percentile
FROM categorized
WHERE troponin_category IN ('Normal', 'Borderline', 'Elevated')
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;