WITH ami_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),

first_abnormal_labs AS (
  SELECT
    l.hadm_id,
    COUNT(DISTINCT l.itemid) AS lab_instability_score
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    ami_cohort a
  ON
    l.hadm_id = a.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (
      l.flag = 'abnormal'
      OR
      (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
    )
  GROUP BY
    l.hadm_id
),

general_abnormal_labs AS (
  SELECT
    l.hadm_id,
    COUNT(DISTINCT l.itemid) AS abnormal_lab_count
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  WHERE
    l.flag = 'abnormal'
    OR
    (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY
    l.hadm_id
)

SELECT
  -- 75th percentile of instability score
  APPROX_QUANTILES(COALESCE(f.lab_instability_score, 0), 100)[OFFSET(75)] AS percentile_75_lab_instability_score,

  -- Average abnormal labs in AMI cohort
  AVG(COALESCE(f.lab_instability_score, 0)) AS avg_abnormal_labs_ami,

  -- Average abnormal labs in general inpatients
  AVG(COALESCE(g.abnormal_lab_count, 0)) AS avg_abnormal_labs_general,

  -- Average LOS and mortality in AMI cohort
  AVG(a.los_days) AS avg_los_days,
  AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
  ami_cohort a
LEFT JOIN
  first_abnormal_labs f
ON
  a.hadm_id = f.hadm_id
LEFT JOIN
  general_abnormal_labs g
ON
  a.hadm_id = g.hadm_id;