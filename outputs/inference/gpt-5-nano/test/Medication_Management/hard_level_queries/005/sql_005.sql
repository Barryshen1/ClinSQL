WITH hepatic_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON ddi.icd_code = di.icd_code AND ddi.icd_version = di.icd_version
  WHERE (p.gender = 'M' OR p.gender = 'Male' OR p.gender = 'm')
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(ddi.long_title) LIKE '%hepatic%'
),
meds_72h AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    COUNT(DISTINCT ie.itemid) AS mcs
  FROM hepatic_cohort AS h
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    ON ie.subject_id = h.subject_id
   AND ie.hadm_id = h.hadm_id
   AND ie.starttime >= h.admittime
   AND ie.starttime < TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR)
  GROUP BY
    h.subject_id,
    h.hadm_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag
),
observations AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag,
    m.mcs,
    TIMESTAMP_DIFF(m.dischtime, m.admittime, SECOND) / 86400.0 AS los_days,
    -- 30-day readmission flag: exists a subsequent admission within 30 days after discharge
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE a2.subject_id = m.subject_id
          AND a2.hadm_id != m.hadm_id
          AND a2.admittime >= m.dischtime
          AND a2.admittime < TIMESTAMP_ADD(m.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_30d
  FROM meds_72h AS m
),
augmented AS (
  SELECT
    o.*,
    NTILE(5) OVER (ORDER BY mcs ASC) AS quintile
  FROM observations AS o
)
SELECT
  quintile,
  COUNT(*) AS n,
  MIN(mcs) AS min_score,
  MAX(mcs) AS max_score,
  AVG(mcs) AS mean_score,
  AVG(los_days) AS mean_los_days,
  100.0 * AVG(CAST(hospital_expire_flag AS INT64)) AS in_hospital_mortality_percent,
  100.0 * AVG(CAST(readmit_30d AS INT64)) AS thirty_day_readmission_percent
FROM augmented
GROUP BY quintile
ORDER BY quintile;