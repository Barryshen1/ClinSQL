WITH first_stays AS (
  SELECT subject_id, stay_id, hadm_id, intime, outtime
  FROM (
    SELECT subject_id, stay_id, hadm_id, intime, outtime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
avg_map AS (
  SELECT fs.stay_id, AVG(ce.valuenum) AS avg_map
  FROM first_stays fs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = fs.stay_id
  WHERE ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fs.intime
    AND ce.charttime <= fs.outtime
  GROUP BY fs.stay_id
  HAVING avg_map IS NOT NULL
),
has_stroke AS (
  SELECT hadm_id,
         MAX(CASE
           WHEN (icd_version = 9 AND LEFT(icd_code, 3) IN ('430', '431', '432', '433', '434', '436'))
             OR (icd_version = 10 AND LEFT(icd_code, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64'))
           THEN 1
           ELSE 0
         END) AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT
  CASE
    WHEN am.avg_map < 65 THEN '<65'
    WHEN am.avg_map < 75 THEN '65-74'
    WHEN am.avg_map < 85 THEN '75-84'
    ELSE '>=85'
  END AS map_category,
  COUNT(*) AS patient_counts,
  SUM(COALESCE(hs.has_stroke, 0)) AS stroke_counts,
  ROUND(SUM(COALESCE(hs.has_stroke, 0)) * 100.0 / COUNT(*), 2) AS stroke_rate_percent
FROM first_stays fs
JOIN avg_map am ON fs.stay_id = am.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON fs.subject_id = p.subject_id
LEFT JOIN has_stroke hs ON fs.hadm_id = hs.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 56 AND 66
GROUP BY 1
ORDER BY
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    ELSE 4
  END;