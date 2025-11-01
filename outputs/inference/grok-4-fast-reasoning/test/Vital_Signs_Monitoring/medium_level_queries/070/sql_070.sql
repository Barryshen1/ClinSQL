WITH aki AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 10 AND STARTS_WITH(icd_code, 'N17')) 
        OR (icd_version = 9 AND STARTS_WITH(icd_code, '584')) 
      THEN 1 
      ELSE 0 
    END) AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
spo2 AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON ce.stay_id = ic.stay_id
  WHERE ce.itemid = 220277
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 100
    AND ce.charttime >= ic.intime
    AND ce.charttime < TIMESTAMP_ADD(ic.intime, INTERVAL 1 DAY)
  GROUP BY ce.stay_id
)
SELECT 
  spo2_bin,
  COUNT(*) AS n,
  ROUND(AVG(s.avg_spo2), 2) AS mean_spo2,
  ROUND(APPROX_QUANTILES(s.avg_spo2, 2)[OFFSET(1)], 2) AS median_spo2,
  ROUND(APPROX_QUANTILES(s.avg_spo2, 4)[OFFSET(3)] - APPROX_QUANTILES(s.avg_spo2, 4)[OFFSET(1)], 2) AS iqr_spo2,
  ROUND(AVG(COALESCE(a.has_aki, 0)) * 100, 1) AS aki_rate_pct
FROM (
  SELECT 
    s.stay_id,
    s.avg_spo2,
    CASE 
      WHEN s.avg_spo2 < 90 THEN '<90'
      WHEN s.avg_spo2 >= 90 AND s.avg_spo2 < 93 THEN '90-92'
      WHEN s.avg_spo2 >= 93 AND s.avg_spo2 <= 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_bin
  FROM spo2 s
) s
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic 
  ON s.stay_id = ic.stay_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON ic.subject_id = p.subject_id
LEFT JOIN aki a 
  ON ic.hadm_id = a.hadm_id
WHERE p.gender = 'F' 
  AND p.anchor_age = 90
GROUP BY spo2_bin
ORDER BY CASE spo2_bin 
  WHEN '<90' THEN 1 
  WHEN '90-92' THEN 2 
  WHEN '93-95' THEN 3 
  ELSE 4 
END;