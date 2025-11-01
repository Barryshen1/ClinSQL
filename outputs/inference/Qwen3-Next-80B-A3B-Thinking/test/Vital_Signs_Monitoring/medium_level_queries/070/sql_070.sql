WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 90 AND 100
),
icu_stays AS (
  SELECT i.stay_id, i.hadm_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_filtered p ON i.subject_id = p.subject_id
),
spo2_first24 AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    AVG(c.valuenum) AS avg_spo2
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
    AND c.itemid = 220277
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '24' HOUR
  GROUP BY i.stay_id, i.hadm_id
),
aki_diagnosis AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
),
combined AS (
  SELECT 
    s.stay_id,
    s.avg_spo2,
    COALESCE(a.has_aki, 0) AS has_aki
  FROM spo2_first24 s
  LEFT JOIN aki_diagnosis a ON s.hadm_id = a.hadm_id
)
SELECT 
  CASE 
    WHEN avg_spo2 < 90 THEN '<90'
    WHEN avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
    WHEN avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
    ELSE '>95'
  END AS spo2_category,
  COUNT(*) AS N,
  AVG(avg_spo2) AS mean,
  APPROX_QUANTILES(avg_spo2, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)] AS iqr,
  AVG(CAST(has_aki AS FLOAT64)) AS aki_rate
FROM combined
GROUP BY spo2_category
ORDER BY spo2_category;