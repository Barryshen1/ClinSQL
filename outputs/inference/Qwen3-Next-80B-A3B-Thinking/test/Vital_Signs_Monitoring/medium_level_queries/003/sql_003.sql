WITH icu_stays AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    anchor_age + (EXTRACT(YEAR FROM a.admittime) - anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (anchor_age + (EXTRACT(YEAR FROM a.admittime) - anchor_year)) BETWEEN 71 AND 81
),
temp_avg AS (
  SELECT
    i.stay_id,
    AVG(c.valuenum) AS avg_temp
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE c.itemid = 223761
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '48' HOUR
  GROUP BY i.stay_id
),
mi_diagnosis AS (
  SELECT
    a.hadm_id,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%') 
      THEN 1 ELSE 0 
    END) AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  GROUP BY a.hadm_id
),
combined AS (
  SELECT
    i.stay_id,
    t.avg_temp,
    m.has_mi
  FROM icu_stays i
  LEFT JOIN temp_avg t ON i.stay_id = t.stay_id
  LEFT JOIN mi_diagnosis m ON i.hadm_id = m.hadm_id
  WHERE t.avg_temp IS NOT NULL
)
SELECT
  CASE
    WHEN avg_temp < 36.0 THEN '<36.0'
    WHEN avg_temp >= 36.0 AND avg_temp < 38.0 THEN '36.0–37.9'
    ELSE '≥38.0'
  END AS temp_category,
  AVG(avg_temp) AS mean_temp,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_temp) AS median_temp,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY avg_temp) AS q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_temp) AS q3,
  (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_temp) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY avg_temp)) AS iqr,
  SUM(has_mi) / COUNT(*) AS mi_rate
FROM combined
GROUP BY temp_category;