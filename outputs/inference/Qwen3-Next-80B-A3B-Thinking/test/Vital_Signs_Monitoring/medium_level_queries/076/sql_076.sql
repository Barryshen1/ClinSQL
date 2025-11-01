WITH age_filtered AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 48 AND 58
),

hr_avg AS (
  SELECT 
    i.stay_id,
    AVG(c.valuenum) AS avg_hr
  FROM age_filtered i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE 
    c.itemid = 211
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '48 hours'
  GROUP BY i.stay_id
),

aki_flag AS (
  SELECT 
    i.stay_id,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE 
          i.hadm_id = d.hadm_id
          AND (
            (d.icd_version = '9' AND d.icd_code LIKE '584%')
            OR (d.icd_version = '10' AND d.icd_code LIKE 'N17%')
          )
      ) THEN 1
      ELSE 0
    END AS has_aki
  FROM age_filtered i
)

SELECT 
  CASE 
    WHEN h.avg_hr < 60 THEN '<60'
    WHEN h.avg_hr BETWEEN 60 AND 99 THEN '60-99'
    WHEN h.avg_hr BETWEEN 100 AND 119 THEN '100-119'
    WHEN h.avg_hr >= 120 THEN '>=120'
  END AS hr_category,
  COUNT(*) AS total_stays,
  SUM(a.has_aki) AS aki_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_distribution,
  ROUND(100.0 * SUM(a.has_aki) / COUNT(*), 2) AS aki_rate
FROM hr_avg h
JOIN aki_flag a ON h.stay_id = a.stay_id
GROUP BY hr_category
ORDER BY hr_category;