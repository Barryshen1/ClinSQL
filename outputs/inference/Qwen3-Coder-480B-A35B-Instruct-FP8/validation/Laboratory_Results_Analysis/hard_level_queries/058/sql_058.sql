WITH target_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      dd.long_title LIKE '%acute coronary%'
      OR dd.long_title LIKE '%myocardial infarction%'
      OR dd.icd_code IN ('410', '4100', '4101', '4102', '4103', '4104', '4105', '4106', '4107', '4108', '4109', '4111', 'I21', 'I22', 'I23', 'I24')
    )
),

lab_instability AS (
  SELECT
    tp.stay_id,
    COUNT(*) AS instability_score
  FROM
    target_patients tp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON tp.hadm_id = l.hadm_id
  WHERE
    l.flag = 'abnormal'
    AND l.charttime >= tp.icu_intime
    AND l.charttime <= DATETIME_ADD(tp.icu_intime, INTERVAL 48 HOUR)
  GROUP BY
    tp.stay_id
),

percentile_90 AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
  FROM
    lab_instability
  LIMIT 1
),

cohort_metrics AS (
  SELECT
    'High Instability (Top 10%)' AS cohort,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality,
    AVG(los_days) AS mean_los,
    AVG(CASE WHEN li.instability_score > 0 THEN 1.0 ELSE 0.0 END) AS critical_lab_rate
  FROM
    target_patients tp
  LEFT JOIN
    lab_instability li
    ON tp.stay_id = li.stay_id
  CROSS JOIN
    percentile_90 p90
  WHERE
    COALESCE(li.instability_score, 0) >= p90.p90_score

  UNION ALL

  SELECT
    'General Inpatients (40-50 Female ACS)' AS cohort,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality,
    AVG(los_days) AS mean_los,
    AVG(CASE WHEN li.instability_score > 0 THEN 1.0 ELSE 0.0 END) AS critical_lab_rate
  FROM
    target_patients tp
  LEFT JOIN
    lab_instability li
    ON tp.stay_id = li.stay_id
)

SELECT * FROM cohort_metrics
ORDER BY cohort;