WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
),
spo2_avg AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.itemid = 220277  -- SpO2
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),
aki_flags AS (
  SELECT 
    hadm_id,
    1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%') OR
    (icd_version = 10 AND (icd_code LIKE 'N17%' OR icd_code = 'N19'))
  GROUP BY hadm_id
),
combined_data AS (
  SELECT 
    c.stay_id,
    s.avg_spo2,
    COALESCE(a.aki_flag, 0) AS aki_flag,
    CASE 
      WHEN s.avg_spo2 < 90 THEN '<90'
      WHEN s.avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
      WHEN s.avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
      WHEN s.avg_spo2 > 95 THEN '>95'
    END AS spo2_bin
  FROM cohort c
  INNER JOIN spo2_avg s 
    ON c.stay_id = s.stay_id
  LEFT JOIN aki_flags a 
    ON c.hadm_id = a.hadm_id
)
SELECT 
  spo2_bin,
  COUNT(*) AS N,
  AVG(avg_spo2) AS mean_spo2,
  APPROX_QUANTILES(avg_spo2, 100)[OFFSET(50)] AS median_spo2,
  APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)] AS iqr,
  SUM(aki_flag) / COUNT(*) AS aki_rate
FROM combined_data
GROUP BY spo2_bin
ORDER BY 
  CASE spo2_bin
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
  END;