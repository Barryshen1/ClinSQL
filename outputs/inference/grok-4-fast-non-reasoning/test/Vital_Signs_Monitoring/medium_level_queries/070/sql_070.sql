WITH demo_stays AS (
  -- Filter female patients aged 90-100 with ICU stays
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND i.first_careunit IS NOT NULL
),

sp02_first24 AS (
  -- Calculate average SpO2 in first 24h per stay
  SELECT 
    ds.subject_id,
    ds.stay_id,
    ds.hadm_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM 
    demo_stays ds
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON ds.subject_id = ce.subject_id 
    AND ds.hadm_id = ce.hadm_id
    AND ds.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220277  -- Pulse oximetry %SpO2
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime >= ds.intime
    AND ce.charttime < TIMESTAMP_ADD(ds.intime, INTERVAL 24 HOUR)
  GROUP BY 
    ds.subject_id, ds.stay_id, ds.hadm_id
  HAVING 
    avg_spo2 IS NOT NULL  -- Ensure valid average
),

binned_spo2 AS (
  -- Bin the averages
  SELECT 
    subject_id,
    stay_id,
    hadm_id,
    avg_spo2,
    CASE 
      WHEN avg_spo2 < 90 THEN '<90'
      WHEN avg_spo2 >= 90 AND avg_spo2 <= 92 THEN '90-92'
      WHEN avg_spo2 >= 93 AND avg_spo2 <= 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_bin
  FROM 
    sp02_first24
),

aki_flags AS (
  -- Flag admissions with AKI diagnosis using ICD codes
  SELECT 
    subject_id,
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 'ICD-9' AND STARTS_WITH(icd_code, '584'))
        OR (icd_version = 'ICD-10' AND STARTS_WITH(icd_code, 'N17')) THEN 1
      ELSE 0
    END) AS has_aki
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY 
    subject_id, hadm_id
)

SELECT 
  b.spo2_bin,
  COUNT(*) AS N,
  ROUND(AVG(b.avg_spo2), 2) AS mean_spo2,
  ROUND(PERCENTILE_CONT(b.avg_spo2, 0.5) OVER (PARTITION BY b.spo2_bin), 2) AS median_spo2,
  ROUND(PERCENTILE_CONT(b.avg_spo2, 0.25) OVER (PARTITION BY b.spo2_bin), 2) AS q1_spo2,
  ROUND(PERCENTILE_CONT(b.avg_spo2, 0.75) OVER (PARTITION BY b.spo2_bin), 2) AS q3_spo2,
  ROUND(AVG(COALESCE(af.has_aki, 0)), 3) AS aki_rate
FROM 
  binned_spo2 b
LEFT JOIN 
  aki_flags af
ON b.subject_id = af.subject_id AND b.hadm_id = af.hadm_id
GROUP BY 
  b.spo2_bin
ORDER BY 
  CASE b.spo2_bin 
    WHEN '<90' THEN 1 
    WHEN '90-92' THEN 2 
    WHEN '93-95' THEN 3 
    ELSE 4 
  END;