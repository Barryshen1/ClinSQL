WITH cohort_pancreatitis AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu
    ON a.hadm_id = icu.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
      OR
      (d.icd_version = 9 AND d.icd_code = '5770')
    )
),

lab_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    STDDEV(l.valuenum) AS instability_score
  FROM
    cohort_pancreatitis c
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents l
    ON c.hadm_id = l.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND l.charttime >= c.intime
    AND l.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND LOWER(d.label) IN (
      'wbc', 'hematocrit', 'platelets',
      'sodium', 'potassium', 'chloride', 'bun', 'creatinine', 'glucose',
      'ast', 'alt', 'bilirubin', 'albumin', 'calcium',
      'lactate'
    )
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

quintiles AS (
  SELECT
    ls.subject_id,
    ls.hadm_id,
    ls.stay_id,
    cp.intime,
    cp.los,
    cp.hospital_expire_flag,
    ls.instability_score,
    NTILE(5) OVER (ORDER BY ls.instability_score) AS score_quintile
  FROM
    lab_scores ls
  JOIN
    cohort_pancreatitis cp
    ON ls.stay_id = cp.stay_id
),

quintile_stats AS (
  SELECT
    score_quintile,
    COUNT(*) AS patient_count,
    AVG(instability_score) AS mean_instability,
    AVG(los) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CASE WHEN EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.labevents l2
      WHERE l2.hadm_id = q.hadm_id
        AND l2.flag = 'abnormal'
        AND l2.charttime >= DATETIME_SUB(q.intime, INTERVAL 0 HOUR)
        AND l2.charttime <= DATETIME_ADD(q.intime, INTERVAL 48 HOUR)
    ) THEN 1 ELSE 0 END) AS pct_critical_labs
  FROM
    quintiles q
  GROUP BY
    score_quintile
),

age_matched_controls AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),

control_critical_pct AS (
  SELECT
    AVG(CASE WHEN l.flag = 'abnormal' THEN 1 ELSE 0 END) AS pct_critical_labs_control
  FROM
    age_matched_controls c
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents l
    ON c.hadm_id = l.hadm_id
  WHERE
    l.charttime IS NOT NULL
)

SELECT
  q.*,
  c.pct_critical_labs_control
FROM
  quintile_stats q
CROSS JOIN
  control_critical_pct c
ORDER BY
  score_quintile;