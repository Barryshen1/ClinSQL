WITH base_population AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 65 AND 75
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'K85%'
    )
),
lab_instability AS (
  SELECT
    bp.hadm_id,
    bp.los,
    bp.hospital_expire_flag,
    COUNT(le.labevent_id) AS instability_score
  FROM base_population bp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON bp.hadm_id = le.hadm_id
    AND le.charttime >= bp.admittime
    AND le.charttime <= TIMESTAMP_ADD(bp.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'critical'
  GROUP BY bp.hadm_id, bp.los, bp.hospital_expire_flag
),
quintile_assignment AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY instability_score) AS quintile
  FROM lab_instability
)
SELECT
  quintile,
  COUNT(*) AS count,
  AVG(instability_score) AS mean_instability,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(CASE WHEN instability_score > 0 THEN 1.0 ELSE 0 END) * 100 AS pct_critical_labs
FROM quintile_assignment
GROUP BY quintile
ORDER BY quintile;