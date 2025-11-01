WITH sbp_data AS (
  SELECT
    i.subject_id,
    MIN(c.valuenum) AS min_sbp,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
    AND c.itemid = 220050  -- Systolic BP
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '72' HOUR
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
  GROUP BY i.subject_id, i.los, a.hospital_expire_flag
  HAVING min_sbp IS NOT NULL
),
percentile_calc AS (
  SELECT
    COUNT(CASE WHEN min_sbp <= 85 THEN 1 END) * 100.0 / COUNT(*) AS percentile
  FROM sbp_data
),
quartiles AS (
  SELECT
    min_sbp,
    los,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY min_sbp) AS quartile
  FROM sbp_data
)
SELECT
  (SELECT percentile FROM percentile_calc) AS percentile,
  AVG(los) AS avg_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality
FROM quartiles
WHERE quartile = 1;