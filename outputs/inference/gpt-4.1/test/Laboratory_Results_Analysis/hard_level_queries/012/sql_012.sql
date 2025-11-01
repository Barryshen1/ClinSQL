WITH ami_patients AS (
  -- Identify male inpatients aged 44-54 with AMI
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      -- AMI ICD-9: 410.x, ICD-10: I21.x
      (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '410')
      OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I21')
    )
),

lab_instability AS (
  -- For each AMI admission, count lab instability and critical labs in first 72h
  SELECT
    ap.subject_id,
    ap.hadm_id,
    COUNTIF(
      l.valuenum IS NOT NULL
      AND l.ref_range_lower IS NOT NULL
      AND l.ref_range_upper IS NOT NULL
      AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
    ) AS instability_score,
    COUNTIF(l.flag = 'critical') AS critical_lab_count
  FROM
    ami_patients ap
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON ap.subject_id = l.subject_id AND ap.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN ap.admittime AND TIMESTAMP_ADD(ap.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ap.subject_id, ap.hadm_id
),

ami_summary AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.instability_score,
    l.critical_lab_count,
    TIMESTAMP_DIFF(ap.dischtime, ap.admittime, HOUR)/24.0 AS los_days,
    ap.hospital_expire_flag
  FROM
    lab_instability l
    INNER JOIN ami_patients ap
      ON l.subject_id = ap.subject_id AND l.hadm_id = ap.hadm_id
),

-- General inpatient cohort (same age/gender, but NOT AMI)
general_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id NOT IN (
      SELECT hadm_id FROM ami_patients
    )
),

general_lab_critical AS (
  SELECT
    gp.subject_id,
    gp.hadm_id,
    COUNTIF(l.flag = 'critical') AS critical_lab_count
  FROM
    general_patients gp
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON gp.subject_id = l.subject_id AND gp.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN gp.admittime AND TIMESTAMP_ADD(gp.admittime, INTERVAL 72 HOUR)
  GROUP BY
    gp.subject_id, gp.hadm_id
)

SELECT
  -- 75th percentile of instability score in AMI cohort
  APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS ami_75th_percentile_instability_score,
  -- Mean critical lab count in AMI cohort
  AVG(critical_lab_count) AS ami_mean_critical_lab_count,
  -- Mean critical lab count in general cohort
  (SELECT AVG(critical_lab_count) FROM general_lab_critical) AS general_mean_critical_lab_count,
  -- Mean LOS (days) in AMI cohort
  AVG(los_days) AS ami_mean_los_days,
  -- Mortality rate in AMI cohort
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS ami_mortality_rate
FROM
  ami_summary
;