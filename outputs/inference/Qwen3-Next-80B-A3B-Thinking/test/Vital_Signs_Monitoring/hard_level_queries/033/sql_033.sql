WITH target_scores AS (
  SELECT
    CAST(c.value AS FLOAT64) AS sapsii_score,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
    AND c.itemid = 228285  -- SAPS II score itemid
    AND c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND c.value IS NOT NULL
),
percentile_calc AS (
  SELECT
    SAFE_DIVIDE(COUNTIF(sapsii_score <= 80) * 100.0, COUNT(*)) AS percentile_of_80
  FROM target_scores
),
decile_calc AS (
  SELECT
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM (
    SELECT
      los,
      hospital_expire_flag,
      NTILE(10) OVER (ORDER BY sapsii_score DESC) AS decile
    FROM target_scores
  )
  WHERE decile = 1
)
SELECT
  percentile_of_80,
  avg_los,
  mortality_rate
FROM percentile_calc, decile_calc;