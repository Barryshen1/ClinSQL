WITH ards_cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data`.mimiciv_3_1_hosp.patients p
  JOIN `physionet-data`.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN `physionet-data`.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data`.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (LOWER(did.long_title) LIKE '%ards%' OR LOWER(did.long_title) LIKE '%acute respiratory distress syndrome%')
),

non_ards_cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data`.mimiciv_3_1_hosp.patients p
  JOIN `physionet-data`.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data`.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN `physionet-data`.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (LOWER(did.long_title) LIKE '%ards%' OR LOWER(did.long_title) LIKE '%acute respiratory distress syndrome%')
    )
),

lab_events_critical AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.flag
  FROM `physionet-data`.mimiciv_3_1_hosp.labevents le
  JOIN `physionet-data`.mimiciv_3_1_hosp.admissions a ON le.hadm_id = a.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.flag IN ('H', 'L', 'abnormal')
),

lab_counts_ards AS (
  SELECT 
    ac.subject_id,
    COUNT(*) AS lab_event_count
  FROM ards_cohort ac
  JOIN lab_events_critical le ON ac.hadm_id = le.hadm_id
  GROUP BY ac.subject_id
),

lab_counts_non_ards AS (
  SELECT 
    nac.subject_id,
    COUNT(*) AS lab_event_count
  FROM non_ards_cohort nac
  JOIN lab_events_critical le ON nac.hadm_id = le.hadm_id
  GROUP BY nac.subject_id
),

threshold AS (
  SELECT PERCENTILE_CONT(lab_event_count, 0.75) WITHIN GROUP (ORDER BY lab_event_count) AS p75_threshold
  FROM lab_counts_ards
),

high_risk_ards AS (
  SELECT ac.subject_id, ac.hospital_expire_flag, 
         DATETIME_DIFF(ac.dischtime, ac.admittime, DAY) AS los
  FROM ards_cohort ac
  JOIN lab_counts_ards lca ON ac.subject_id = lca.subject_id
  JOIN threshold t ON lca.lab_event_count >= t.p75_threshold
)

SELECT 
  t.p75_threshold,
  AVG(CAST(hra.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(hra.los) AS mean_los_days,
  AVG(lca.lab_event_count) AS avg_lab_events_high_risk_ards,
  AVG(lcna.lab_event_count) AS avg_lab_events_non_ards
FROM threshold t
LEFT JOIN high_risk_ards hra ON TRUE
LEFT JOIN lab_counts_ards lca ON hra.subject_id = lca.subject_id
LEFT JOIN lab_counts_non_ards lcna ON TRUE
GROUP BY t.p75_threshold;