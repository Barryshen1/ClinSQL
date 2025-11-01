WITH acs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE (
    d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '411.1')
    OR
    d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code = 'I20.0')
  )
),
filtered_admissions AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM acs_admissions
  WHERE gender = 'F'
    AND age >= 46
    AND age <= 56
),
first_tnt AS (
  SELECT
    hadm_id,
    valuenum AS first_tnt
  FROM (
    SELECT
      hadm_id,
      charttime,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 51277
      AND valuenum IS NOT NULL
  )
  WHERE rn = 1
)
SELECT
  CASE
    WHEN ft.first_tnt < 0.014 THEN 'Normal'
    WHEN ft.first_tnt >= 0.014 AND ft.first_tnt < 0.052 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS tnt_category,
  COUNT(*) AS count_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(fa.los_days), 2) AS mean_los_days
FROM filtered_admissions fa
INNER JOIN first_tnt ft
  ON fa.hadm_id = ft.hadm_id
GROUP BY 1
ORDER BY
  CASE tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    ELSE 3
  END;