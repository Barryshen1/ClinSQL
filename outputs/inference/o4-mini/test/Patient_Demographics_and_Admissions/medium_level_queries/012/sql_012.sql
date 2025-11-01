WITH male_75_85 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.dischtime IS NOT NULL
),

los_calc AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    discharge_location,
    -- Compute LOS in whole days
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    male_75_85
),

categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
      WHEN hospital_expire_flag = 0
           AND UPPER(discharge_location) LIKE '%HOME%' THEN 'Discharged Home'
      ELSE 'Discharged to Facility'
    END AS disposition
  FROM
    los_calc
)

SELECT
  disposition,
  COUNT(*)                                            AS total_n,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END)      AS n_ge7,
  SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END)      AS n_le7,
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END),
    COUNT(*)
  )                                                    AS prop_ge7,
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END),
    COUNT(*)
  )                                                    AS pct_rank_7
FROM
  categorized
GROUP BY
  disposition
ORDER BY
  disposition;