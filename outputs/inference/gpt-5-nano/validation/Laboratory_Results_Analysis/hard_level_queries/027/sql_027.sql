WITH cohort AS (
  -- Select male patients aged 89-99 with a diagnosis compatible with lower GI bleeding
  SELECT
    a.hadm_id,
    a.subject_id,
    TIMESTAMP(a.admittime) AS admittime,
    TIMESTAMP(a.dischtime) AS dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON di.icd_code = dic.icd_code
   AND di.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND REGEXP_CONTAINS(LOWER(dic.long_title), r'(lower.*gi.*bleed|lower.*gastrointestinal.*bleed|gastrointestinal bleed)')
),
labs72 AS (
  -- 72-hour lab instability within 72h of admission
  SELECT
    l.hadm_id,
    SUM(CASE
          WHEN l.valuenum IS NOT NULL
               AND (
                   (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
                   OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
                 )
               OR REGEXP_CONTAINS(LOWER(COALESCE(l.flag, '')), r'critical')
             THEN 1
          ELSE 0
        END) AS instability_score,
    MAX(CASE
          WHEN REGEXP_CONTAINS(LOWER(COALESCE(l.flag, '')), r'critical')
            THEN 1
          ELSE 0
        END) AS any_critical_lab
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN cohort AS c
    ON l.hadm_id = c.hadm_id
  WHERE TIMESTAMP(l.charttime) BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY l.hadm_id
),
summary AS (
  -- Per-admission summary: instability score, any critical lab within 72h, and LOS
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    IFNULL(ls.instability_score, 0) AS instability_score,
    IFNULL(ls.any_critical_lab, 0) AS any_critical_lab,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / 3600.0 AS los_hours
  FROM cohort AS c
  LEFT JOIN labs72 AS ls
    ON c.hadm_id = ls.hadm_id
),
quintiles AS (
  -- Stratify by instability score into 5 quintiles
  SELECT
    hadm_id,
    instability_score,
    any_critical_lab,
    los_hours,
    hospital_expire_flag,
    NTILE(5) OVER (ORDER BY instability_score DESC) AS quintile
  FROM summary
)
SELECT
  quintile,
  AVG(los_hours) AS avg_los_hours,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(any_critical_lab) AS quintile_critical_lab_rate,
  (SELECT AVG(hospital_expire_flag) FROM summary) AS general_mortality_rate,
  (SELECT AVG(any_critical_lab) FROM summary) AS general_critical_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;