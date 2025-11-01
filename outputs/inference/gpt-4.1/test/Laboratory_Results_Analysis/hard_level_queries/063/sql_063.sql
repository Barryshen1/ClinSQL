WITH pe_admissions AS (
  -- Identify admissions for female patients aged 53-63 with pulmonary embolism
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      -- ICD-10: I26.x, ICD-9: 415.1x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I26'))
      OR
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^4151'))
    )
),

lab_instability AS (
  -- For each PE admission, count distinct abnormal labs in first 72h
  SELECT
    pa.subject_id,
    pa.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM
    pe_admissions pa
    JOIN physionet-data.mimiciv_3_1_hosp.labevents le
      ON pa.subject_id = le.subject_id AND pa.hadm_id = le.hadm_id
  WHERE
    le.flag IS NOT NULL
    AND LOWER(le.flag) != 'normal'
    AND le.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 72 HOUR)
  GROUP BY
    pa.subject_id, pa.hadm_id
),

percentile_75 AS (
  -- Compute 75th percentile of instability score
  SELECT
    PERCENTILE_CONT(instability_score, 0.75) OVER () AS instability_75th
  FROM
    lab_instability
  LIMIT 1
),

high_instability AS (
  -- Admissions with instability score >= 75th percentile
  SELECT
    li.subject_id,
    li.hadm_id,
    li.instability_score
  FROM
    lab_instability li
    CROSS JOIN percentile_75 p
  WHERE
    li.instability_score >= p.instability_75th
),

high_group_stats AS (
  -- For high instability group: mortality, mean LOS, critical-lab rate
  SELECT
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN pa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    AVG(TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY)) AS mean_los_days
  FROM
    high_instability hi
    JOIN pe_admissions pa
      ON hi.subject_id = pa.subject_id AND hi.hadm_id = pa.hadm_id
),

high_group_critical_labs AS (
  -- Critical-lab rate for high instability group (per admission)
  SELECT
    AVG(critical_lab_count) AS critical_lab_rate
  FROM (
    SELECT
      hi.subject_id,
      hi.hadm_id,
      COUNT(DISTINCT le.labevent_id) AS critical_lab_count
    FROM
      high_instability hi
      JOIN physionet-data.mimiciv_3_1_hosp.labevents le
        ON hi.subject_id = le.subject_id AND hi.hadm_id = le.hadm_id
      JOIN pe_admissions pa
        ON hi.subject_id = pa.subject_id AND hi.hadm_id = pa.hadm_id
    WHERE
      le.flag IS NOT NULL
      AND LOWER(le.flag) = 'critical'
      AND le.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 72 HOUR)
    GROUP BY
      hi.subject_id, hi.hadm_id
  )
),

all_inpatients AS (
  -- All admissions for comparison
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
),

all_inpatients_critical_labs AS (
  -- Critical-lab rate for all inpatients (per admission)
  SELECT
    AVG(critical_lab_count) AS critical_lab_rate
  FROM (
    SELECT
      ai.subject_id,
      ai.hadm_id,
      COUNT(DISTINCT le.labevent_id) AS critical_lab_count
    FROM
      all_inpatients ai
      JOIN physionet-data.mimiciv_3_1_hosp.labevents le
        ON ai.subject_id = le.subject_id AND ai.hadm_id = le.hadm_id
    WHERE
      le.flag IS NOT NULL
      AND LOWER(le.flag) = 'critical'
      AND le.charttime BETWEEN ai.admittime AND TIMESTAMP_ADD(ai.admittime, INTERVAL 72 HOUR)
    GROUP BY
      ai.subject_id, ai.hadm_id
  )
)

SELECT
  p.instability_75th AS instability_score_75th_percentile,
  hgs.n_admissions AS high_score_n_admissions,
  ROUND(100.0 * hgs.n_deaths / hgs.n_admissions, 2) AS high_score_mortality_percent,
  ROUND(hgs.mean_los_days, 2) AS high_score_mean_los_days,
  ROUND(hgcl.critical_lab_rate, 2) AS high_score_critical_lab_rate,
  ROUND(aicl.critical_lab_rate, 2) AS all_inpatients_critical_lab_rate
FROM
  percentile_75 p,
  high_group_stats hgs,
  high_group_critical_labs hgcl,
  all_inpatients_critical_labs aicl;