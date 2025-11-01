WITH eligible AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    -- approximate age at admission
    AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 55 AND 65
    -- asthma exacerbation: admission has asthma-related diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
        ON di.icd_code = d.icd_code
       AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%asthma%'
    )
),

-- 2) Lab instability score: count abnormal labs in first 48 hours
lab_metrics AS (
  SELECT e.hadm_id,
         SUM(CASE
               WHEN l.valuenum IS NOT NULL
                    AND l.ref_range_lower IS NOT NULL
                    AND l.ref_range_upper IS NOT NULL
                    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
               THEN 1 ELSE 0
             END) AS lab_instability_score
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = e.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = e.hadm_id
   AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY e.hadm_id
),

-- 3) 95th percentile threshold (approximate)
thresholds AS (
  SELECT q[OFFSET(94)] AS threshold_95
  FROM (
    SELECT APPROX_QUANTILES(lab_instability_score, 100) AS q
    FROM lab_metrics
  )
),

-- 4) Critical lab flag per admission (within first 48h)
critical_flags AS (
  SELECT e.hadm_id,
         MAX(CASE WHEN LOWER(COALESCE(l.flag, '')) LIKE '%critical%' THEN 1.0 ELSE 0.0 END) AS has_critical
  FROM eligible e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = e.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = e.hadm_id
   AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY e.hadm_id
),

-- 5) Assemble per-admission metrics: group label, LOS, mortality, critical flag
joined AS (
  SELECT lm.hadm_id,
         CASE WHEN lm.lab_instability_score >= t.threshold_95 THEN 'top_95' ELSE 'general' END AS group_type,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/86400.0 AS los_days,
         CASE WHEN a.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END AS in_hosp_mort,
         cf.has_critical AS has_critical
  FROM lab_metrics lm
  JOIN eligible e ON e.hadm_id = lm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = lm.hadm_id
  LEFT JOIN critical_flags cf
    ON cf.hadm_id = lm.hadm_id
  CROSS JOIN thresholds t
)

-- 6) Final aggregation: top_95 vs general, with threshold_95 reported
SELECT
  t.threshold_95 AS threshold_95,
  j.group_type,
  COUNT(*) AS n_admissions,
  AVG(j.los_days) AS avg_los_days,
  AVG(j.in_hosp_mort) AS in_hosp_mortality_rate,
  AVG(j.has_critical) AS critical_lab_rate
FROM joined AS j
CROSS JOIN thresholds AS t
GROUP BY t.threshold_95, j.group_type
ORDER BY j.group_type;