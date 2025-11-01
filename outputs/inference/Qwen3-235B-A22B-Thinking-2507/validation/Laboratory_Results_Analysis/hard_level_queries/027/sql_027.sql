WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN ('K570', 'K571', 'K572', 'K573', 'K574', 'K575', 'K625')
    )
),
lab_instability AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(l.labevent_id) AS instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag IN ('critical', 'critical high', 'critical low')
  GROUP BY c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM lab_instability
),
general_rate AS (
  SELECT 
    AVG(critical_count) AS general_critical_lab_rate
  FROM (
    SELECT 
      a.hadm_id,
      COUNT(l.labevent_id) AS critical_count
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
      AND l.flag IN ('critical', 'critical high', 'critical low')
    GROUP BY a.hadm_id
  )
)
SELECT 
  q.quintile,
  AVG(TIMESTAMP_DIFF(q.dischtime, q.admittime, SECOND) / 86400.0) AS avg_los_days,
  AVG(q.hospital_expire_flag) AS mortality_rate,
  AVG(q.instability_score) AS quintile_critical_lab_rate,
  g.general_critical_lab_rate
FROM quintiles q
CROSS JOIN general_rate g
GROUP BY q.quintile, g.general_critical_lab_rate
ORDER BY q.quintile;