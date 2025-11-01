WITH target_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(di.long_title) LIKE '%status epilepticus%'
),
control_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(di.long_title) LIKE '%status epilepticus%'
    )
),
med_complexity AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS num_distinct_drugs
  FROM (
    SELECT hadm_id, admittime FROM target_patients
    UNION ALL
    SELECT hadm_id, admittime FROM control_patients
  ) p
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr 
    ON p.hadm_id = pr.hadm_id 
    AND pr.starttime >= p.admittime 
    AND pr.starttime < TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR)
  WHERE pr.starttime IS NOT NULL
  GROUP BY p.hadm_id
),
quartile AS (
  SELECT PERCENTILE_CONT(num_distinct_drugs, 0.75) OVER () AS top_quartile_threshold
  FROM med_complexity mc
  JOIN target_patients tp ON mc.hadm_id = tp.hadm_id
  LIMIT 1
),
group_metrics AS (
  SELECT 
    'Status Epilepticus' AS group_name,
    AVG(mc.num_distinct_drugs) AS avg_med_complexity,
    AVG(TIMESTAMP_DIFF(tp.dischtime, tp.admittime, HOUR) / 24.0) AS avg_los_days,
    AVG(CAST(tp.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM target_patients tp
  JOIN med_complexity mc ON tp.hadm_id = mc.hadm_id
  GROUP BY 1

  UNION ALL

  SELECT 
    'General Inpatients' AS group_name,
    AVG(mc.num_distinct_drugs) AS avg_med_complexity,
    AVG(TIMESTAMP_DIFF(cp.dischtime, cp.admittime, HOUR) / 24.0) AS avg_los_days,
    AVG(CAST(cp.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM control_patients cp
  JOIN med_complexity mc ON cp.hadm_id = mc.hadm_id
  GROUP BY 1
),
top_quartile_metrics AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(tp.dischtime, tp.admittime, HOUR) / 24.0) AS los_top_quartile,
    AVG(CAST(tp.hospital_expire_flag AS FLOAT64)) AS mortality_top_quartile
  FROM target_patients tp
  JOIN med_complexity mc ON tp.hadm_id = mc.hadm_id
  CROSS JOIN quartile q
  WHERE mc.num_distinct_drugs >= q.top_quartile_threshold
)
SELECT 
  gm.group_name,
  gm.avg_med_complexity,
  gm.avg_los_days,
  gm.mortality_rate,
  NULL AS los_top_quartile,
  NULL AS mortality_top_quartile
FROM group_metrics gm

UNION ALL

SELECT 
  'Status Epilepticus (Top Quartile)' AS group_name,
  NULL AS avg_med_complexity,
  tq.los_top_quartile,
  tq.mortality_top_quartile,
  tq.los_top_quartile,
  tq.mortality_top_quartile
FROM top_quartile_metrics tq
ORDER BY group_name;