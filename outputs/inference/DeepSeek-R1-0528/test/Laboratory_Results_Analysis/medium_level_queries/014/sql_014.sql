WITH acs_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '410%')
      OR (di.icd_version = 9 AND di.icd_code IN ('411.1', '411.81'))
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I22%')
      OR (di.icd_version = 10 AND di.icd_code = 'I20.0')
    )
),
first_troponin AS (
  SELECT
    aa.hadm_id,
    le.valuenum AS troponin_value
  FROM
    acs_admissions aa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON aa.hadm_id = le.hadm_id
    AND aa.subject_id = le.subject_id
  WHERE
    le.itemid = 51003  -- Troponin T
    AND le.valuenum IS NOT NULL
    AND LOWER(le.valueuom) = 'ng/ml'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY aa.hadm_id ORDER BY le.charttime) = 1
)
SELECT
  CASE
    WHEN troponin_value <= 0.01 THEN 'Normal'
    WHEN troponin_value > 0.01 AND troponin_value <= 0.1 THEN 'Borderline'
    WHEN troponin_value > 0.1 THEN 'Elevated'
  END AS troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM
  first_troponin
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;