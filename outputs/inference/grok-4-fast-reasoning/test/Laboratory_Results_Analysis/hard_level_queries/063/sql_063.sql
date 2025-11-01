WITH pe_cohort AS (
  SELECT DISTINCT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '415.1%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I26%')
        )
    )
),
pe_scores AS (
  SELECT 
    pc.*,
    COUNTIF(le.flag IS NOT NULL) * 1.0 / NULLIF(COUNT(le.labevent_id), 0) AS instability_score
  FROM pe_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = pc.subject_id 
    AND le.hadm_id = pc.hadm_id
    AND le.charttime >= pc.admittime
    AND le.charttime < TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
  GROUP BY 
    pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime, pc.hospital_expire_flag
),
threshold AS (
  SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS thresh
  FROM pe_scores
),
high_risk_pe AS (
  SELECT ps.*
  FROM pe_scores ps
  CROSS JOIN threshold t
  WHERE ps.instability_score >= t.thresh
),
general_cohort AS (
  SELECT DISTINCT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
general_scores AS (
  SELECT 
    gc.*,
    COUNTIF(le.flag IS NOT NULL) * 1.0 / NULLIF(COUNT(le.labevent_id), 0) AS instability_score
  FROM general_cohort gc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = gc.subject_id 
    AND le.hadm_id = gc.hadm_id
    AND le.charttime >= gc.admittime
    AND le.charttime < TIMESTAMP_ADD(gc.admittime, INTERVAL 72 HOUR)
  GROUP BY 
    gc.subject_id, gc.hadm_id, gc.admittime, gc.dischtime
)
SELECT 
  (SELECT thresh FROM threshold) AS percentile_75,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS mortality_pct,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days,
  ROUND(AVG(instability_score), 4) AS pe_high_critical_rate,
  ROUND((SELECT AVG(instability_score) FROM general_scores), 4) AS general_inpatient_critical_rate
FROM high_risk_pe;