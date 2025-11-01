WITH ACS_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      LOWER(dd.long_title) LIKE '%acute myocardial infarction%' OR
      LOWER(dd.long_title) LIKE '%unstable angina%' OR
      LOWER(dd.long_title) LIKE '%acute coronary syndrome%' OR
      LOWER(dd.long_title) LIKE '%myocardial infarction%'
    )
),

initial_troponin AS (
  SELECT le.hadm_id,
         le.charttime,
         le.valuenum,
         le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE (
         LOWER(dli.label) LIKE '%troponin%' AND
         LOWER(dli.label) LIKE '%t%'
        )
    AND le.hadm_id IN (SELECT hadm_id FROM ACS_admissions)
),

initial_troponin_per_admission AS (
  SELECT hadm_id, valuenum
  FROM (
    SELECT hadm_id, valuenum,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM initial_troponin
  )
  WHERE rn = 1 AND valuenum IS NOT NULL
),

troponin_cat AS (
  SELECT hadm_id,
         valuenum,
         CASE
           WHEN valuenum <= 0.04 THEN 'normal'
           WHEN valuenum > 0.04 AND valuenum <= 0.39 THEN 'borderline'
           WHEN valuenum > 0.39 THEN 'elevated'
           ELSE NULL
         END AS category
  FROM initial_troponin_per_admission
  WHERE valuenum IS NOT NULL
),

-- total number of admissions contributing to the analysis
total_adms AS (
  SELECT COUNT(DISTINCT hadm_id) AS total
  FROM troponin_cat
),

-- basic category statistics: counts, percentages, mean
cat_stats AS (
  SELECT c.category,
         COUNT(*) AS count,
         ROUND(COUNT(*) * 100.0 / MAX(ta.total), 1) AS percent,
         AVG(c.valuenum) AS mean_troponin
  FROM troponin_cat c
  CROSS JOIN total_adms ta
  GROUP BY c.category
),

-- quartiles per category to derive median and IQR
quartiles AS (
  SELECT category,
         APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM troponin_cat
  GROUP BY category
)

SELECT s.category,
       s.count,
       s.percent,
       s.mean_troponin,
       (q.quantiles)[OFFSET(2)] AS median_troponin,
       (q.quantiles)[OFFSET(1)] AS q1_troponin,
       (q.quantiles)[OFFSET(3)] AS q3_troponin,
       ( (q.quantiles)[OFFSET(3)] - (q.quantiles)[OFFSET(1)] ) AS iqr_troponin
FROM cat_stats s
JOIN quartiles q
  ON s.category = q.category
ORDER BY s.category;