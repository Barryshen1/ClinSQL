WITH AP_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND dd.icd_code LIKE 'K85%'  -- ICD-10 acute pancreatitis
),

labs_72h AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN AP_cohort c
      ON l.subject_id = c.subject_id
      AND l.hadm_id = c.hadm_id
  WHERE
    l.valuenum IS NOT NULL
    AND l.charttime BETWEEN c.admittime
      AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),

instability AS (
  SELECT
    hadm_id,
    SUM(transition_flag) AS lab_instability_score
  FROM (
    SELECT
      hadm_id,
      itemid,
      charttime,
      ABS(abnormal_flag - LAG(abnormal_flag) OVER (
        PARTITION BY hadm_id, itemid
        ORDER BY charttime
      )) AS transition_flag
    FROM (
      SELECT
        hadm_id,
        itemid,
        charttime,
        CASE
          WHEN valuenum < ref_range_lower THEN 1
          WHEN valuenum > ref_range_upper THEN 1
          ELSE 0
        END AS abnormal_flag
      FROM labs_72h
    )
  )
  GROUP BY hadm_id
),

AP_scores AS (
  SELECT
    c.*,
    COALESCE(i.lab_instability_score, 0) AS lab_instability_score
  FROM AP_cohort c
  LEFT JOIN instability i
    ON c.hadm_id = i.hadm_id
),

P90_value AS (
  SELECT
    quantiles[OFFSET(90)] AS p90_score
  FROM (
    SELECT
      APPROX_QUANTILES(lab_instability_score, 100) AS quantiles
    FROM AP_scores
  )
),

AP_high AS (
  SELECT
    s.*
  FROM AP_scores s
  CROSS JOIN P90_value v
  WHERE s.lab_instability_score >= v.p90_score
),

AP_high_summary AS (
  SELECT
    'AP_HighInstability' AS cohort,
    COUNT(*) AS n_patients,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los_hours)/24.0 AS mean_los_days
  FROM AP_high
),

AP_high_labrates AS (
  SELECT
    l.itemid,
    i.label,
    100.0 * AVG(
      CASE
        WHEN l.valuenum < l.ref_range_lower THEN 1
        WHEN l.valuenum > l.ref_range_upper THEN 1
        ELSE 0
      END
    ) AS pct_abnormal
  FROM labs_72h l
  JOIN AP_high h
    ON l.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` i
    ON l.itemid = i.itemid
  GROUP BY l.itemid, i.label
),

General_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND dd.icd_code LIKE 'K85%'
    )
),

labs_72h_gen AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN General_cohort g
      ON l.subject_id = g.subject_id
      AND l.hadm_id = g.hadm_id
  WHERE
    l.valuenum IS NOT NULL
    AND l.charttime BETWEEN g.admittime
      AND TIMESTAMP_ADD(g.admittime, INTERVAL 72 HOUR)
),

General_summary AS (
  SELECT
    'GeneralInpatients' AS cohort,
    COUNT(*) AS n_patients,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los_hours)/24.0 AS mean_los_days
  FROM General_cohort
),

General_labrates AS (
  SELECT
    l.itemid,
    i.label,
    100.0 * AVG(
      CASE
        WHEN l.valuenum < l.ref_range_lower THEN 1
        WHEN l.valuenum > l.ref_range_upper THEN 1
        ELSE 0
      END
    ) AS pct_abnormal
  FROM labs_72h_gen l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` i
    ON l.itemid = i.itemid
  GROUP BY l.itemid, i.label
)

-- Final patient‐level summaries
SELECT * FROM AP_high_summary
UNION ALL
SELECT * FROM General_summary;

-- Per‐lab comparison
SELECT
  COALESCE(a.itemid, g.itemid) AS itemid,
  COALESCE(a.label, g.label) AS lab_label,
  a.pct_abnormal AS pct_abnormal_AP_high,
  g.pct_abnormal AS pct_abnormal_General
FROM AP_high_labrates a
FULL JOIN General_labrates g
  ON a.itemid = g.itemid
ORDER BY lab_label;