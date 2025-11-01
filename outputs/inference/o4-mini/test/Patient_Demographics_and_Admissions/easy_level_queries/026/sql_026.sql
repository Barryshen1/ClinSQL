WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
cabg_first_admissions AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.deathtime,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON fa.subject_id = pr.subject_id
      AND fa.hadm_id = pr.hadm_id
      AND pr.icd_version = 9
      AND pr.icd_code LIKE '36.1%'  -- ICD-9 CABG codes
  WHERE
    fa.rn = 1
),
death_times AS (
  SELECT
    TIMESTAMP_DIFF(deathtime, admittime, HOUR) AS hours_to_death
  FROM
    cabg_first_admissions
  WHERE
    hospital_expire_flag = 1
    AND deathtime IS NOT NULL
)
SELECT
  -- 25th percentile of in-hospital time-to-death (in hours)
  APPROX_QUANTILES(hours_to_death, 100)[OFFSET(25)] AS pct25_hours_to_death
FROM
  death_times;