WITH heart_failure_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, p.gender, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 37 AND 47
),
heart_failure_admissions AS (
  SELECT DISTINCT c.subject_id, c.hadm_id, c.anchor_age, c.gender, c.admittime, c.dischtime, c.hospital_expire_flag
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  JOIN heart_failure_icds hfi
    ON d.icd_code = hfi.icd_code AND d.icd_version = hfi.icd_version
),
labs_critically_abnormal AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.ref_range_lower,
    l.ref_range_upper,
    -- Critically abnormal: >20% above/below reference range
    CASE
      WHEN l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower * 0.8 THEN 1
      WHEN l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper * 1.2 THEN 1
      ELSE 0
    END AS is_critically_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.valuenum IS NOT NULL
),
labs_in_72h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    l.itemid,
    l.charttime,
    l.is_critically_abnormal
  FROM cohort c
  JOIN labs_critically_abnormal l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),
instability_score AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT itemid) AS instability_score
  FROM labs_in_72h
  WHERE is_critically_abnormal = 1
  GROUP BY subject_id, hadm_id
),
-- Heart failure cohort metrics
hf_metrics AS (
  SELECT
    'Heart Failure' AS cohort,
    MAX(COALESCE(i.instability_score, 0)) AS max_instability_score,
    COUNTIF(COALESCE(i.instability_score, 0) > 0) / COUNT(*) AS critical_event_rate,
    AVG(TIMESTAMP_DIFF(hfa.dischtime, hfa.admittime, HOUR)/24.0) AS avg_los_days,
    AVG(CAST(hfa.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM heart_failure_admissions hfa
  LEFT JOIN instability_score i
    ON hfa.subject_id = i.subject_id AND hfa.hadm_id = i.hadm_id
),
-- General cohort metrics
general_metrics AS (
  SELECT
    'General Inpatients' AS cohort,
    MAX(COALESCE(i.instability_score, 0)) AS max_instability_score,
    COUNTIF(COALESCE(i.instability_score, 0) > 0) / COUNT(*) AS critical_event_rate,
    AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24.0) AS avg_los_days,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM cohort c
  LEFT JOIN instability_score i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
)
SELECT * FROM hf_metrics
UNION ALL
SELECT * FROM general_metrics
ORDER BY cohort;