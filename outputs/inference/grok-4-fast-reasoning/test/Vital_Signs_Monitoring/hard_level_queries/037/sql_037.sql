WITH vital_definitions AS (
  SELECT 220045 AS itemid, 'HR' AS vtype, 100 AS threshold
  UNION ALL
  SELECT 220052, 'MAP', 65
  UNION ALL
  SELECT 220210, 'RR', 20
),
all_icu AS (
  SELECT 
    i.stay_id, i.subject_id, i.hadm_id, i.intime, i.outtime, i.los,
    p.gender, p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
),
target_stays AS (
  SELECT s.*
  FROM all_icu s
  WHERE s.gender = 'M' 
    AND s.anchor_age BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = s.subject_id 
        AND d.hadm_id = s.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
vitals AS (
  SELECT 
    ce.subject_id, ce.hadm_id, ce.stay_id, ce.itemid, ce.charttime, ce.valuenum,
    vd.vtype, vd.threshold
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN all_icu a 
    ON ce.subject_id = a.subject_id 
    AND ce.hadm_id = a.hadm_id 
    AND ce.stay_id = a.stay_id
  INNER JOIN vital_definitions vd 
    ON ce.itemid = vd.itemid
  WHERE ce.charttime >= a.intime 
    AND ce.charttime <= LEAST(a.outtime, TIMESTAMP_ADD(a.intime, INTERVAL 72 HOUR))
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
),
stay_vitals AS (
  SELECT 
    stay_id,
    vtype,
    COUNT(*) AS total_readings,
    COUNTIF(
      (vtype = 'MAP' AND valuenum < threshold) 
      OR (vtype != 'MAP' AND valuenum > threshold)
    ) AS abnormal_count
  FROM vitals
  GROUP BY stay_id, vtype, threshold
),
stay_metrics AS (
  SELECT 
    a.stay_id, a.los, a.hospital_expire_flag,
    SUM(
      CASE WHEN sv.total_readings > 0 
        THEN 1.0 * sv.abnormal_count / sv.total_readings 
        ELSE 0 END
    ) / 3.0 AS instability_score,
    MAX(
      CASE WHEN sv.vtype = 'HR' AND sv.total_readings > 0 
        THEN 1.0 * sv.abnormal_count / sv.total_readings 
        ELSE 0 END
    ) AS prop_tachycardia,
    MAX(
      CASE WHEN sv.vtype = 'MAP' AND sv.total_readings > 0 
        THEN 1.0 * sv.abnormal_count / sv.total_readings 
        ELSE 0 END
    ) AS prop_hypotension,
    MAX(
      CASE WHEN sv.vtype = 'RR' AND sv.total_readings > 0 
        THEN 1.0 * sv.abnormal_count / sv.total_readings 
        ELSE 0 END
    ) AS prop_tachypnea
  FROM all_icu a
  LEFT JOIN stay_vitals sv 
    ON a.stay_id = sv.stay_id
  GROUP BY a.stay_id, a.los, a.hospital_expire_flag
),
target_metrics AS (
  SELECT sm.*
  FROM stay_metrics sm
  INNER JOIN target_stays t 
    ON sm.stay_id = t.stay_id
),
percentile_99 AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(99)] AS p99_score
  FROM target_metrics
),
quartile_75 AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS q75_score
  FROM target_metrics
),
unstable_quartile AS (
  SELECT *
  FROM target_metrics
  WHERE instability_score >= (SELECT q75_score FROM quartile_75)
),
unstable_avgs AS (
  SELECT 
    AVG(prop_tachycardia) AS avg_tachycardia,
    AVG(prop_hypotension) AS avg_hypotension,
    AVG(prop_tachypnea) AS avg_tachypnea,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM unstable_quartile
),
all_icu_avgs AS (
  SELECT 
    AVG(prop_tachycardia) AS avg_tachycardia,
    AVG(prop_hypotension) AS avg_hypotension,
    AVG(prop_tachypnea) AS avg_tachypnea,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM stay_metrics
),
comparison AS (
  SELECT 'Most Unstable Quartile' AS cohort, avg_tachycardia, avg_hypotension, avg_tachypnea, avg_los, mortality_rate
  FROM unstable_avgs
  UNION ALL
  SELECT 'All ICU Population' AS cohort, avg_tachycardia, avg_hypotension, avg_tachypnea, avg_los, mortality_rate
  FROM all_icu_avgs
)
SELECT 
  p99.p99_score,
  c.cohort,
  ROUND(c.avg_tachycardia, 4) AS avg_tachycardia_prop,
  ROUND(c.avg_hypotension, 4) AS avg_hypotension_prop,
  ROUND(c.avg_tachypnea, 4) AS avg_tachypnea_prop,
  ROUND(c.avg_los, 2) AS avg_icu_los_days,
  ROUND(c.mortality_rate, 4) AS mortality_rate
FROM percentile_99 p99
CROSS JOIN comparison c
ORDER BY CASE WHEN c.cohort = 'Most Unstable Quartile' THEN 1 ELSE 2 END;