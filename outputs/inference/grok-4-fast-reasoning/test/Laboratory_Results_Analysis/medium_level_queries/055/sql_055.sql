WITH qualifying_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 81 AND 91
    AND (
      (di.icd_version = '9' AND (di.icd_code LIKE '410.%' OR di.icd_code LIKE '786.5%'))
      OR
      (di.icd_version = '10' AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'R07%'))
    )
),
index_tnt AS (
  SELECT
    qa.subject_id,
    qa.hadm_id,
    le.valuenum,
    qa.los_days
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON qa.subject_id = le.subject_id AND qa.hadm_id = le.hadm_id
  WHERE le.itemid = 3655
    AND le.valuenum IS NOT NULL
    AND le.charttime >= qa.admittime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY qa.subject_id, qa.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT
  CASE
    WHEN valuenum <= 0.014 THEN 'Normal'
    WHEN valuenum > 0.014 AND valuenum <= 0.052 THEN 'Borderline'
    ELSE 'Myocardial injury'
  END AS hs_tnt_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM index_tnt
GROUP BY hs_tnt_category
ORDER BY
  CASE hs_tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial injury' THEN 3
  END;