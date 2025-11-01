WITH cohort AS (
  -- Base cohort: males 80-90 with sepsis
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'A41%') OR
      (d.icd_version = '9' AND (d.icd_code LIKE '038%' OR d.icd_code = '99591'))
    )
    AND a.hadm_id IS NOT NULL  -- Ensure valid admission
  QUALIFY rn = 1  -- First admission per patient
),

med_events AS (
  -- Medications in first 24h from prescriptions and ICU inputs
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    pr.drug AS med_name,
    NULL AS itemid,
    pr.route,
    'prescription' AS source,
    CASE 
      WHEN LOWER(pr.drug) IN ('amiodarone', 'haloperidol', 'ondansetron') THEN 1 ELSE 0 
    END AS qt_flag,
    CASE 
      WHEN LOWER(pr.drug) IN ('heparin', 'enoxaparin', 'clopidogrel') THEN 1 ELSE 0 
    END AS bleed_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE pr.drug IS NOT NULL 
    AND pr.starttime >= c.admittime 
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)

  UNION ALL

  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    d.label AS med_name,
    ie.itemid,
    NULL AS route,  -- Inputs may not have route
    'input' AS source,
    CASE 
      WHEN ie.itemid IN (225798, 221862, 227410, 222589, 228351) THEN 1 ELSE 0 
    END AS qt_flag,
    CASE 
      WHEN ie.itemid IN (225351, 225282, 225807, 226531) THEN 1 ELSE 0 
    END AS bleed_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
    ON c.subject_id = ie.subject_id AND c.hadm_id = ie.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
    ON ie.itemid = d.itemid
  WHERE d.category LIKE '%Drug%'  -- Drug category only
    AND ie.starttime >= c.admittime 
    AND ie.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
    AND ie.statusdescription != 'Rewritten'  -- Exclude canceled
),

drug_flags AS (
  -- Flags for QT and bleeding risk (aggregated per admission)
  SELECT 
    m.hadm_id,
    MAX(m.qt_flag) AS on_qt,
    MAX(m.bleed_flag) AS on_bleed,
    MAX(CASE WHEN m.qt_flag = 1 AND m.bleed_flag = 1 THEN 1 ELSE 0 END) AS both
  FROM med_events m
  GROUP BY m.hadm_id
),

mcs_scores AS (
  -- Compute MCS: unique drug-route combos
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT CONCAT(COALESCE(m.med_name, ''), COALESCE(m.route, ''))) AS mcs,
    COALESCE(f.both, 0) AS both_group
  FROM cohort c
  LEFT JOIN med_events m ON c.hadm_id = m.hadm_id
  LEFT JOIN drug_flags f ON c.hadm_id = f.hadm_id
  GROUP BY c.hadm_id, COALESCE(f.both, 0)
),

dist_summary AS (
  -- Distribution and percentiles by group
  SELECT 
    both_group,
    'distribution' AS metric,
    COUNT(*) AS n_patients,
    AVG(mcs) AS mean_mcs,
    APPROX_QUANTILES(mcs, 4)[OFFSET(1)] AS p25_mcs,
    APPROX_QUANTILES(mcs, 4)[OFFSET(2)] AS p50_mcs,
    APPROX_QUANTILES(mcs, 4)[OFFSET(3)] AS p75_mcs,
    ARRAY_TO_STRING(APPROX_QUANTILES(mcs, 100), ', ') AS approx_percentiles  -- Approx 0-100th for distribution/ranks
  FROM mcs_scores
  GROUP BY both_group
),

top_summary AS (
  -- LOS/mortality for top quartile by group
  SELECT 
    ms.both_group,
    'top_quartile' AS metric,
    COUNT(*) AS n_top,
    AVG(TIMESTAMPDIFF(DAY, c.admittime, c.dischtime)) AS mean_los_days,
    AVG(CASE WHEN c.hospital_expire_flag = 1 OR c.deathtime IS NOT NULL THEN 1.0 ELSE 0 END) AS mortality_rate
  FROM mcs_scores ms
  INNER JOIN cohort c ON ms.hadm_id = c.hadm_id
  QUALIFY NTILE(4) OVER (PARTITION BY ms.both_group ORDER BY ms.mcs DESC) = 1  -- Top 25% per group
  GROUP BY ms.both_group
)

SELECT * FROM dist_summary
UNION ALL
SELECT both_group, metric, n_top AS n_patients, mean_los_days AS mean_mcs, NULL AS p25_mcs, NULL AS p50_mcs, NULL AS p75_mcs, NULL AS approx_percentiles
FROM top_summary
ORDER BY both_group, metric;