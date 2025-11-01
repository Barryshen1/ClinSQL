WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
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
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND LOWER(d.long_title) LIKE '%heart failure%'
),

lab_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT l.itemid) AS instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.subject_id = l.subject_id
    AND l.charttime >= c.intime
    AND l.charttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  WHERE
    l.flag IN ('abnormal', 'critical')
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id
),

summary_stats AS (
  SELECT
    MAX(instability_score) AS max_instability_score,
    AVG(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) AS critical_event_rate,
    AVG(c.icu_los) AS avg_icu_los,
    AVG(c.hospital_expire_flag) AS mortality_rate
  FROM
    cohort c
  LEFT JOIN
    lab_scores ls
  ON
    c.stay_id = ls.stay_id
)

SELECT * FROM summary_stats;