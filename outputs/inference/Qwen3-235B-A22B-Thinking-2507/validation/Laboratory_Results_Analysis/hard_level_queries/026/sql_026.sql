WITH hepatic_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN ('K7200', 'K7201', 'K7290', 'K7291')
    )
),
general_cohort AS (
  SELECT 
    hadm_id,
    admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
hepatic_critical_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(l.labevent_id) AS critical_count
  FROM hepatic_cohort h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON h.hadm_id = l.hadm_id
    AND l.flag = 'abnormal'
    AND l.charttime >= h.admittime
    AND l.charttime <= DATETIME_ADD(h.admittime, INTERVAL 48 HOUR)
  GROUP BY h.hadm_id
),
general_critical_counts AS (
  SELECT 
    g.hadm_id,
    COUNT(l.labevent_id) AS critical_count
  FROM general_cohort g
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON g.hadm_id = l.hadm_id
    AND l.flag = 'abnormal'
    AND l.charttime >= g.admittime
    AND l.charttime <= DATETIME_ADD(g.admittime, INTERVAL 48 HOUR)
  GROUP BY g.hadm_id
)
SELECT 
  (SELECT MAX(l.valuenum) 
   FROM hepatic_cohort h
   INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
     ON h.hadm_id = l.hadm_id
   WHERE l.itemid = 51237
     AND l.charttime >= h.admittime
     AND l.charttime <= DATETIME_ADD(h.admittime, INTERVAL 48 HOUR)
  ) AS max_instability_score,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
  (SELECT AVG(critical_count) FROM hepatic_critical_counts) AS avg_critical_labs_hepatic,
  (SELECT AVG(critical_count) FROM general_critical_counts) AS avg_critical_labs_general
FROM hepatic_cohort;