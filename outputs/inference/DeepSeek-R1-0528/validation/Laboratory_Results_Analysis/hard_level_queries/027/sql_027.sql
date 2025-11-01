WITH gi_bleed_codes AS (
  SELECT icd_code, icd_version
  FROM UNNEST([
    STRUCT('5781' AS icd_code, 9 AS icd_version),
    ('5789', 9),
    ('K625', 10),
    ('K922', 10)
  ])
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN gi_bleed_codes gc
        ON di.icd_code = gc.icd_code
        AND di.icd_version = gc.icd_version
      WHERE di.hadm_id = a.hadm_id
    )
),
critical_labs AS (
  SELECT
    c.hadm_id,
    l.labevent_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  WHERE
    l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag IS NOT NULL
),
patient_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los,
    c.hospital_expire_flag,
    COUNT(cl.labevent_id) AS score
  FROM cohort c
  LEFT JOIN critical_labs cl
    ON c.hadm_id = cl.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.los, c.hospital_expire_flag
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY score) AS quintile,
    AVG(score) OVER () AS overall_critical_lab_rate
  FROM patient_scores
)
SELECT
  quintile,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  AVG(score) AS critical_lab_rate,
  MAX(overall_critical_lab_rate) AS overall_critical_lab_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;