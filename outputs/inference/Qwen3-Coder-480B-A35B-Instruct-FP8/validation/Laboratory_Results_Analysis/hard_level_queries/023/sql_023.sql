WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
  ON
    d.icd_code = did.icd_code
    AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND did.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND (
        did.icd_code LIKE 'I21%'
        OR did.icd_code LIKE 'I22%'
        OR did.icd_code = 'I252'
      ))
    )
),

lab_instability AS (
  SELECT
    c.hadm_id,
    COUNT(*) AS lab_instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND (
      l.flag != 'normal'
      OR l.valuenum < l.ref_range_lower
      OR l.valuenum > l.ref_range_upper
    )
  GROUP BY
    c.hadm_id
),

score_percentile AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS p75_score
  FROM
    lab_instability
),

patients_p75 AS (
  SELECT
    c.*,
    COALESCE(s.lab_instability_score, 0) AS lab_instability_score
  FROM
    cohort c
  LEFT JOIN
    lab_instability s
  ON
    c.hadm_id = s.hadm_id
  WHERE
    COALESCE(s.lab_instability_score, 0) >= (
      SELECT p75_score FROM score_percentile
    )
),

all_cohort_metrics AS (
  SELECT
    'All' AS group_name,
    AVG(hospital_expire_flag) AS mortality,
    AVG(los_days) AS mean_los,
    AVG(CASE WHEN COALESCE(lab_instability_score, 0) > 0 THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM (
    SELECT
      c.*,
      s.lab_instability_score
    FROM
      cohort c
    LEFT JOIN
      lab_instability s
    ON
      c.hadm_id = s.hadm_id
  )
),

p75_metrics AS (
  SELECT
    'P75+' AS group_name,
    AVG(hospital_expire_flag) AS mortality,
    AVG(los_days) AS mean_los,
    AVG(CASE WHEN lab_instability_score > 0 THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM
    patients_p75
)

SELECT * FROM p75_metrics
UNION ALL
SELECT * FROM all_cohort_metrics
ORDER BY group_name;