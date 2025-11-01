WITH hemorrhagic_stroke_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('I60', 'I61', 'I62'))
    )
),

critical_labs AS (
  SELECT
    l.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    hemorrhagic_stroke_patients hsp
    ON l.hadm_id = hsp.hadm_id
  WHERE
    l.flag IN ('abnormal', 'critical')
    AND l.charttime BETWEEN hsp.admittime AND DATETIME_ADD(hsp.admittime, INTERVAL 72 HOUR)
  GROUP BY
    l.hadm_id
),

lab_instability_scores AS (
  SELECT
    hsp.hadm_id,
    COALESCE(cl.critical_lab_count, 0) AS lab_instability_score,
    hsp.hospital_expire_flag,
    hsp.los_days
  FROM
    hemorrhagic_stroke_patients hsp
  LEFT JOIN
    critical_labs cl
    ON hsp.hadm_id = cl.hadm_id
),

percentile_90 AS (
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.9) OVER() AS p90_score
  FROM
    lab_instability_scores
  LIMIT 1
),

patients_ge_p90 AS (
  SELECT
    lis.*
  FROM
    lab_instability_scores lis
  CROSS JOIN
    percentile_90 p90
  WHERE
    lis.lab_instability_score >= p90.p90_score
),

age_matched_cohort AS (
  SELECT
    lis.*
  FROM
    lab_instability_scores lis
)

SELECT
  '>=P90' AS cohort,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  AVG(los_days) AS mean_los_days,
  AVG(lab_instability_score) AS avg_critical_labs_per_patient
FROM
  patients_ge_p90

UNION ALL

SELECT
  'Age-matched cohort' AS cohort,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  AVG(los_days) AS mean_los_days,
  AVG(lab_instability_score) AS avg_critical_labs_per_patient
FROM
  age_matched_cohort;