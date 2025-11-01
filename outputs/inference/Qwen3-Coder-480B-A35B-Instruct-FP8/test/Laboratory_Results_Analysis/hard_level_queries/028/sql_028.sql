WITH cohort_ich AS (
  -- Identify ICH patients: women aged 74–84
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('431', '432.1'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
),

abnormal_labs_72hr AS (
  -- Get abnormal labs in first 72 hours of ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT l.itemid) AS distinct_abnormal_labs
  FROM
    cohort_ich c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.hadm_id = l.hadm_id
  WHERE
    l.charttime >= c.intime
    AND l.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND (
      l.flag = 'abnormal'
      OR (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
    )
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    distinct_abnormal_labs,
    NTILE(5) OVER (ORDER BY distinct_abnormal_labs) AS lab_quintile
  FROM
    abnormal_labs_72hr
),

outcomes AS (
  SELECT
    q.lab_quintile,
    AVG(c.los) AS mean_los,
    AVG(c.hospital_expire_flag) AS mortality_rate,
    COUNT(*) AS patient_count
  FROM
    quintiles q
  JOIN
    cohort_ich c
  ON
    q.stay_id = c.stay_id
  GROUP BY
    q.lab_quintile
),

control_cohort AS (
  -- Age-matched controls: women 74–84 without ICH
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        (d.icd_version = 9 AND d.icd_code IN ('431', '432.1'))
        OR
        (d.icd_version = 10 AND (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
),

control_abnormal_labs AS (
  SELECT
    c.subject_id,
    COUNT(DISTINCT l.itemid) AS control_abnormal_labs
  FROM
    control_cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.hadm_id = l.hadm_id
  WHERE
    l.charttime >= c.intime
    AND l.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND (
      l.flag = 'abnormal'
      OR (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
    )
  GROUP BY
    c.subject_id
),

avg_control_labs AS (
  SELECT
    AVG(control_abnormal_labs) AS avg_control_abnormal_labs
  FROM
    control_abnormal_labs
)

-- Final output
SELECT
  o.lab_quintile,
  o.mean_los,
  o.mortality_rate,
  o.patient_count,
  a.avg_control_abnormal_labs
FROM
  outcomes o
CROSS JOIN
  avg_control_labs a
ORDER BY
  o.lab_quintile;