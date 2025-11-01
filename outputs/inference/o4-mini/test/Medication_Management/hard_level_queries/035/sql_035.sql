WITH cohort AS (
  -- female patients age 40-50
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),
nf_adm AS (
  -- admissions with neutropenic fever diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      USING(icd_code, icd_version)
  WHERE
    LOWER(dd.long_title) LIKE '%neutropenic fever%'
),
complexity AS (
  -- medication complexity score in first 48h: distinct drug count
  SELECT
    c.hadm_id,
    COUNT(DISTINCT rx.drug) AS med_complexity
  FROM
    cohort AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
      ON c.subject_id = rx.subject_id
      AND c.hadm_id    = rx.hadm_id
      AND rx.starttime BETWEEN c.admittime 
                           AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY
    c.hadm_id
),
readmission AS (
  -- flag if readmitted within 30 days
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE
      WHEN MIN(next_adm.admittime) 
           BETWEEN c.dischtime 
                   AND TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      THEN 1 ELSE 0
    END AS readmit_30d
  FROM
    cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS next_adm
      ON c.subject_id = next_adm.subject_id
      AND next_adm.admittime > c.dischtime
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.dischtime
),
base AS (
  -- combine everything and compute LOS
  SELECT
    c.subject_id,
    c.hadm_id,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    c.hospital_expire_flag,
    comp.med_complexity,
    COALESCE(r.readmit_30d, 0) AS readmit_30d
  FROM
    cohort AS c
    JOIN nf_adm AS nf
      USING(subject_id, hadm_id)
    LEFT JOIN complexity AS comp
      USING(hadm_id)
    LEFT JOIN readmission AS r
      USING(subject_id, hadm_id)
),
quartiles AS (
  -- assign quartile by med_complexity
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_complexity) AS complexity_q
  FROM
    base
)
SELECT
  complexity_q AS quartile,
  COUNT(*)                                    AS admission_count,
  ROUND(AVG(med_complexity), 2)               AS mean_complexity,
  MIN(med_complexity)                         AS min_complexity,
  MAX(med_complexity)                         AS max_complexity,
  ROUND(AVG(los_days), 2)                     AS mean_los_days,
  ROUND(100.0 * AVG(hospital_expire_flag), 1) AS pct_mortality,
  ROUND(100.0 * AVG(readmit_30d), 1)          AS pct_30d_readmit
FROM
  quartiles
GROUP BY
  complexity_q
ORDER BY
  complexity_q;