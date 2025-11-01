WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(did.long_title) LIKE '%acute pancreatitis%'
),

key_labs AS (
  SELECT itemid, label
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) IN (
    'amylase', 'lipase', 'creatinine', 'bun', 'wbc', 'glucose', 
    'calcium', 'alt', 'ast', 'bilirubin'
  )
),

reference_ranges AS (
  SELECT 'amylase' AS label, 23 AS ref_range_lower, 100 AS ref_range_upper UNION ALL
  SELECT 'lipase', 10, 140 UNION ALL
  SELECT 'creatinine', 0.6, 1.2 UNION ALL
  SELECT 'bun', 7, 20 UNION ALL
  SELECT 'wbc', 4.0, 11.0 UNION ALL
  SELECT 'glucose', 70, 100 UNION ALL
  SELECT 'calcium', 8.5, 10.5 UNION ALL
  SELECT 'alt', 7, 56 UNION ALL
  SELECT 'ast', 10, 40 UNION ALL
  SELECT 'bilirubin', 0.1, 1.2
),

first_48h_labs AS (
  SELECT
    ep.subject_id,
    ep.hadm_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    le.valueuom,
    rr.ref_range_lower,
    rr.ref_range_upper
  FROM eligible_patients ep
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON ep.subject_id = le.subject_id AND ep.hadm_id = le.hadm_id
  INNER JOIN key_labs kl
    ON le.itemid = kl.itemid
  INNER JOIN reference_ranges rr
    ON kl.label = rr.label
  WHERE le.charttime >= ep.admittime
    AND le.charttime <= TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
),

lab_consecutive_diffs AS (
  SELECT
    subject_id,
    itemid,
    charttime,
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY subject_id, itemid ORDER BY charttime) AS rn
  FROM first_48h_labs
),

lab_differences AS (
  SELECT
    l1.subject_id,
    ABS(l1.valuenum - l2.valuenum) AS diff
  FROM lab_consecutive_diffs l1
  INNER JOIN lab_consecutive_diffs l2
    ON l1.subject_id = l2.subject_id
    AND l1.itemid = l2.itemid
    AND l2.rn = l1.rn - 1
),

instability_scores AS (
  SELECT
    subject_id,
    AVG(diff) AS instability_score
  FROM lab_differences
  GROUP BY subject_id
),

critical_labs AS (
  SELECT DISTINCT
    subject_id,
    1 AS has_critical_lab
  FROM first_48h_labs
  WHERE (valuenum < ref_range_lower OR valuenum > ref_range_upper)
    AND ref_range_lower IS NOT NULL
    AND ref_range_upper IS NOT NULL
),

patient_summary AS (
  SELECT
    es.subject_id,
    COALESCE(es.instability_score, 0.0) AS instability_score,
    COALESCE(cl.has_critical_lab, 0) AS has_critical_lab,
    EXTRACT(EPOCH FROM (ep.dischtime - ep.admittime)) / 3600 / 24 AS los_days,
    ep.hospital_expire_flag
  FROM instability_scores es
  INNER JOIN eligible_patients ep
    ON es.subject_id = ep.subject_id
  LEFT JOIN critical_labs cl
    ON es.subject_id = cl.subject_id
)

SELECT
  NTILE(5) OVER (ORDER BY instability_score) AS quintile,
  COUNT(*) AS count,
  AVG(instability_score) AS mean_instability,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(has_critical_lab) AS pct_critical_labs
FROM patient_summary
GROUP BY quintile
ORDER BY quintile;