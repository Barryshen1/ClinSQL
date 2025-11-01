WITH cohort AS (
  SELECT DISTINCT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
      WHERE diag.subject_id = icu.subject_id
        AND diag.hadm_id = icu.hadm_id
        AND (
          (diag.icd_version = 9
           AND (diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code = '436'))
          OR
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
        )
    )
),
abnormal_counts AS (
  SELECT
    ce.stay_id,
    SUM(
      CASE
        WHEN (ce.itemid = 220045 AND (ce.valuenum < 50 OR ce.valuenum > 130)) THEN 1
        WHEN ce.itemid = 220179 AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
        WHEN ce.itemid = 220180 AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
        WHEN ce.itemid = 220210 AND (ce.valuenum < 10 OR ce.valuenum > 30) THEN 1
        WHEN ce.itemid = 223762 AND (ce.valuenum < 36 OR ce.valuenum > 38) THEN 1
        WHEN ce.itemid = 220277 AND (ce.valuenum < 92 OR ce.valuenum > 100) THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN cohort c
    ON ce.stay_id = c.stay_id
  WHERE ce.itemid IN (220045, 220179, 220180, 220210, 223762, 220277)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY ce.stay_id
),
scores AS (
  SELECT
    c.stay_id,
    COALESCE(ac.instability_score, 0) AS instability_score,
    c.los,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN abnormal_counts ac
    ON c.stay_id = ac.stay_id
),
percentile_calc AS (
  SELECT
    COUNTIF(instability_score <= 80) * 100.0 / COUNT(*) AS percentile_80
  FROM scores
),
top_quartile AS (
  SELECT
    AVG(los) AS avg_los_top,
    AVG(hospital_expire_flag) * 100 AS mortality_top_pct
  FROM (
    SELECT
      los,
      hospital_expire_flag,
      NTILE(4) OVER (ORDER BY instability_score DESC) AS ntile
    FROM scores
  )
  WHERE ntile = 1
)
SELECT
  p.percentile_80,
  t.avg_los_top,
  t.mortality_top_pct
FROM percentile_calc p
CROSS JOIN top_quartile t;