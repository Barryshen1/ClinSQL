WITH base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    di.long_title AS principal_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_cd
    ON a.hadm_id = di_cd.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON di_cd.icd_code = di.icd_code
    AND di_cd.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.insurance = 'Medicare'
    AND di_cd.seq_num = 1  -- principal diagnosis
    AND (
      LOWER(di.long_title) LIKE '%lower gastrointestinal bleeding%'
      OR LOWER(di.long_title) LIKE '%gastrointestinal bleeding%'
      OR LOWER(di.long_title) LIKE '%gib%'
      OR LOWER(di.long_title) LIKE '%colonic bleeding%'
      OR LOWER(di.long_title) LIKE '%rectal bleeding%'
      OR LOWER(di.long_title) LIKE '%lower gi bleed%'
      OR LOWER(di.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(di.long_title) LIKE '%hematochezia%'
      OR LOWER(di.long_title) LIKE '%melena%'
      OR LOWER(di.long_title) LIKE '%anorectal bleeding%'
      OR LOWER(di.long_title) LIKE '%digestive tract hemorrhage%'
      OR LOWER(di.long_title) LIKE '%intestinal bleeding%'
      OR LOWER(di.long_title) LIKE '%bowel bleeding%'
    )
),

readmission_flag AS (
  SELECT
    bc.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = bc.subject_id
          AND a2.admittime > bc.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(bc.dischtime, INTERVAL 30 DAY)
          AND a2.hadm_id != bc.hadm_id
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM
    base_cohort bc
)

SELECT
  ROUND(100.0 * SUM(readmitted_30d) / COUNT(*), 2) AS thirty_day_readmission_rate_percent,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 2)[OFFSET(1)] AS median_los_readmitted_days,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 2)[OFFSET(1)] AS median_los_not_readmitted_days,
  ROUND(100.0 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_greater_than_6_days
FROM
  readmission_flag;