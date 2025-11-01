WITH first_admissions AS (
  -- get each patient's first hospital admission (by admittime)
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN (
    SELECT subject_id, MIN(admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
  ) fa
  ON a.subject_id = fa.subject_id
  AND a.admittime = fa.first_admittime
),

cabg_hadm AS (
  -- identify hadm_ids where a CABG procedure appears (text-based match on procedure description)
  SELECT DISTINCT p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE (
        LOWER(d.long_title) LIKE '%coronary%' AND LOWER(d.long_title) LIKE '%bypass%'
      )
      OR LOWER(d.long_title) LIKE '%cabg%'
),

cohort AS (
  -- join first admissions to patients, restrict by gender and age, and to CABG first admissions
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.deathtime,
    fa.hospital_expire_flag,
    p.anchor_age
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fa.subject_id = p.subject_id
  JOIN cabg_hadm c
    ON fa.hadm_id = c.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
)

SELECT
  COUNT(*) AS cohort_n,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_proportion,
  (
    SELECT
      CASE
        WHEN qs IS NOT NULL AND ARRAY_LENGTH(qs) >= 26 THEN qs[OFFSET(25)]
        ELSE NULL
      END
    FROM (
      SELECT APPROX_QUANTILES(days_to_death_days, 100) AS qs
      FROM (
        SELECT
          TIMESTAMP_DIFF(deathtime, admittime, SECOND) / 86400.0 AS days_to_death_days
        FROM cohort
        WHERE hospital_expire_flag = 1
          AND deathtime IS NOT NULL
          AND admittime IS NOT NULL
          AND TIMESTAMP_DIFF(deathtime, admittime, SECOND) > 0
      )
    )
  ) AS days_to_death_25th_percentile_days
FROM cohort;