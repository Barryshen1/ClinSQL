WITH instability_scores AS (
  SELECT
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    STDDEV(ce.valuenum) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 84 AND 94
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('43401', '43411', '43491'))
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I63.%')
        )
    )
    AND ce.itemid = 220045  -- Heart rate itemid
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id, i.los, a.hospital_expire_flag
  HAVING COUNT(*) >= 10
),
percentile_calc AS (
  SELECT
    (COUNTIF(instability_score <= 80) * 100.0 / COUNT(*)) AS percentile_80
  FROM instability_scores
),
quartile_stats AS (
  SELECT
    AVG(los) AS avg_los_top_quartile,
    AVG(hospital_expire_flag) AS mortality_rate_top_quartile
  FROM (
    SELECT *,
      NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
    FROM instability_scores
  )
  WHERE quartile = 1
)
SELECT
  pc.percentile_80,
  qs.avg_los_top_quartile,
  qs.mortality_rate_top_quartile
FROM percentile_calc pc
CROSS JOIN quartile_stats qs;