WITH population AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = i.hadm_id
        AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    )
),
scores AS (
  SELECT
    p.stay_id,
    p.icu_los,
    p.hospital_expire_flag,
    COALESCE(SUM(
      CASE
        WHEN c.itemid = 220045 AND (c.valuenum < 60 OR c.valuenum > 100) THEN 1
        WHEN c.itemid = 220050 AND (c.valuenum < 90 OR c.valuenum > 120) THEN 1
        WHEN c.itemid = 220056 AND (c.valuenum < 12 OR c.valuenum > 20) THEN 1
        WHEN c.itemid = 223761 AND (c.valuenum < 36 OR c.valuenum > 37.5) THEN 1
        ELSE 0
      END
    ), 0) AS score
  FROM population p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON p.stay_id = c.stay_id
    AND c.charttime BETWEEN p.intime AND DATETIME_ADD(p.intime, INTERVAL 72 HOUR)
    AND c.itemid IN (220045, 220050, 220056, 223761)
  GROUP BY p.stay_id, p.icu_los, p.hospital_expire_flag
),
percentile_calc AS (
  SELECT
    COUNTIF(score <= 75) * 100.0 / COUNT(*) AS percentile
  FROM scores
),
top_decile AS (
  SELECT
    AVG(icu_los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM (
    SELECT
      *,
      NTILE(10) OVER (ORDER BY score DESC) AS decile
    FROM scores
  )
  WHERE decile = 10
)
SELECT
  (SELECT percentile FROM percentile_calc) AS percentile,
  (SELECT avg_los FROM top_decile) AS avg_los,
  (SELECT mortality_rate FROM top_decile) AS mortality_rate;