WITH cohort_acs AS (
  -- Identify female patients aged 53–63 with ACS
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    a.hospital_expire_flag,
    a.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I2[0-4]'))
    )
),

lab_scores AS (
  -- Compute instability score: count of distinct abnormal lab categories in 72h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag,
    c.los,
    COUNT(DISTINCT CASE
      WHEN l.flag = 'abnormal' OR
           SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(d.ref_range_lower AS FLOAT64) OR
           SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(d.ref_range_upper AS FLOAT64)
      THEN d.category
    END) AS instability_score
  FROM
    cohort_acs c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    l.charttime >= c.icu_intime
    AND l.charttime <= DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
    AND (
      l.flag = 'abnormal' OR
      SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(d.ref_range_lower AS FLOAT64) OR
      SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(d.ref_range_upper AS FLOAT64)
    )
    AND d.category IN ('chemistry', 'hematology', 'blood gas', 'cardiac enzymes')
  GROUP BY
    c.subject_id, c.hadm_id, c.hospital_expire_flag, c.los
),

quartiles AS (
  -- Assign quartiles based on instability score
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS score_quartile
  FROM
    lab_scores
),

mortality_los AS (
  -- Aggregate mortality and LOS by quartile
  SELECT
    q.score_quartile,
    COUNT(*) AS patient_count,
    AVG(CASE WHEN q.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS mortality_percent,
    AVG(q.los) AS avg_los
  FROM
    quartiles q
  GROUP BY
    q.score_quartile
),

control_cohort AS (
  -- Define age-matched female controls without ACS
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hadm_id NOT IN (
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%'))
        OR
        (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I2[0-4]'))
    )
),

control_scores AS (
  -- Compute instability scores for controls
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT CASE
      WHEN l.flag = 'abnormal' OR
           SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(d.ref_range_lower AS FLOAT64) OR
           SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(d.ref_range_upper AS FLOAT64)
      THEN d.category
    END) AS instability_score
  FROM
    control_cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    l.charttime >= c.icu_intime
    AND l.charttime <= DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
    AND (
      l.flag = 'abnormal' OR
      SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(d.ref_range_lower AS FLOAT64) OR
      SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(d.ref_range_upper AS FLOAT64)
    )
    AND d.category IN ('chemistry', 'hematology', 'blood gas', 'cardiac enzymes')
  GROUP BY
    c.subject_id, c.hadm_id
),

avg_control_score AS (
  SELECT
    AVG(instability_score) AS avg_control_instability
  FROM
    control_scores
)

-- Final output
SELECT
  m.score_quartile,
  m.patient_count,
  m.mortality_percent,
  m.avg_los,
  a.avg_control_instability
FROM
  mortality_los m
CROSS JOIN
  avg_control_score a
ORDER BY
  m.score_quartile;