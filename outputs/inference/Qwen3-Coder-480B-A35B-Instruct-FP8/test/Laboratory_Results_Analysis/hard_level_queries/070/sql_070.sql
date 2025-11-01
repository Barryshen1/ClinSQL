WITH hemorrhagic_stroke_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.los,
    a.hospital_expire_flag
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
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('431', '4320', '4321', '4329'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I61|^I62'))
    )
),

abnormal_labs_72hr AS (
  SELECT
    l.hadm_id,
    l.itemid,
    COUNT(DISTINCT l.itemid) OVER (PARTITION BY l.hadm_id) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    hemorrhagic_stroke_cohort h
  ON
    l.hadm_id = h.hadm_id
  WHERE
    l.charttime IS NOT NULL
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN h.admittime AND DATETIME_ADD(h.admittime, INTERVAL 72 HOUR)
    AND (
      l.flag = 'abnormal'
      OR l.valuenum < l.ref_range_lower
      OR l.valuenum > l.ref_range_upper
    )
  GROUP BY
    l.hadm_id, l.itemid
),

instability_scores AS (
  SELECT
    h.hadm_id,
    h.los,
    h.hospital_expire_flag,
    COALESCE(a.instability_score, 0) AS instability_score
  FROM
    hemorrhagic_stroke_cohort h
  LEFT JOIN (
    SELECT hadm_id, MAX(instability_score) AS instability_score
    FROM abnormal_labs_72hr
    GROUP BY hadm_id
  ) a
  ON h.hadm_id = a.hadm_id
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM
    instability_scores
),

lab_abnormal_rates AS (
  SELECT
    itemid,
    COUNT(*) AS total_abnormal,
    COUNT(DISTINCT hadm_id) AS patient_count
  FROM
    abnormal_labs_72hr
  GROUP BY
    itemid
),

general_abnormal_labs AS (
  SELECT
    l.itemid,
    COUNT(*) AS total_abnormal_general
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    l.hadm_id = a.hadm_id
  WHERE
    l.charttime IS NOT NULL
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (
      l.flag = 'abnormal'
      OR l.valuenum < l.ref_range_lower
      OR l.valuenum > l.ref_range_upper
    )
  GROUP BY
    l.itemid
)

-- Final output
SELECT
  q.quartile,
  COUNT(DISTINCT q.hadm_id) AS patient_count,
  AVG(q.los) AS avg_los,
  AVG(q.hospital_expire_flag) AS mortality_rate,
  l.label,
  lar.total_abnormal,
  lar.patient_count AS lab_patient_count,
  g.total_abnormal_general
FROM
  quartiles q
LEFT JOIN
  abnormal_labs_72hr a
ON
  q.hadm_id = a.hadm_id
LEFT JOIN
  `physionet-data.mimiciv_3_1_hosp.d_labitems` l
ON
  a.itemid = l.itemid
LEFT JOIN
  lab_abnormal_rates lar
ON
  a.itemid = lar.itemid
LEFT JOIN
  general_abnormal_labs g
ON
  a.itemid = g.itemid
GROUP BY
  q.quartile, l.label, lar.total_abnormal, lar.patient_count, g.total_abnormal_general
ORDER BY
  q.quartile, lar.total_abnormal DESC;