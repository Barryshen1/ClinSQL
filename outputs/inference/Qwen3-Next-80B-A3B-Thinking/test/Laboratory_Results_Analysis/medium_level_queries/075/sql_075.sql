WITH troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%'
),

admissions_with_diagnosis AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code IN ('786.50', '786.51', '786.59')))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07%'))
    )
    AND DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 41 AND 51
),

first_troponin AS (
  SELECT 
    a.hadm_id,
    MIN(l.charttime) AS first_charttime
  FROM admissions_with_diagnosis a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  WHERE l.itemid IN (SELECT itemid FROM troponin_itemids)
    AND l.charttime >= a.admittime
  GROUP BY a.hadm_id
),

troponin_values AS (
  SELECT 
    l.valuenum,
    l.ref_range_upper
  FROM admissions_with_diagnosis a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  JOIN first_troponin ft ON a.hadm_id = ft.hadm_id AND l.charttime = ft.first_charttime
  WHERE l.itemid IN (SELECT itemid FROM troponin_itemids)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
)

SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
  AVG(valuenum) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr
FROM (
  SELECT
    CASE
      WHEN valuenum <= ref_range_upper THEN 'normal'
      WHEN valuenum > ref_range_upper AND valuenum <= 1.5 * ref_range_upper THEN 'borderline'
      ELSE 'elevated'
    END AS category,
    valuenum
  FROM troponin_values
) AS categorized
GROUP BY category
ORDER BY category;