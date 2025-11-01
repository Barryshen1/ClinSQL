WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND di.long_title LIKE '%heart failure%'
    )
),
los_groups AS (
  SELECT
    CASE WHEN los < 8 THEN '<8' ELSE '>=8' END AS los_group,
    COUNT(*) AS N,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
  FROM cohort
  GROUP BY los_group
),
median_death_time AS (
  SELECT
    MEDIAN(TIMESTAMP_DIFF(deathtime, admittime, DAY)) AS median_time
  FROM cohort
  WHERE hospital_expire_flag = 1
)
SELECT
  los_group,
  N,
  mortality_rate,
  NULL AS median_time_to_death
FROM los_groups
UNION ALL
SELECT
  'median_time_to_death',
  NULL,
  NULL,
  median_time
FROM median_death_time;