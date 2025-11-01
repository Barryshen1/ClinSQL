WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    CASE
      WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 'InHospitalDeath'
      ELSE 'Survived'
    END AS death_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE
    p.anchor_age BETWEEN 78 AND 88
    AND UPPER(p.gender) LIKE 'M%'
    AND a.dischtime IS NOT NULL
    -- Require a transfer event for the admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.transfers` AS t
      WHERE t.subject_id = a.subject_id
        AND t.hadm_id = a.hadm_id
        AND UPPER(t.eventtype) LIKE '%TRANSFER%'
    )
),
quantiles AS (
  SELECT
    death_status,
    APPROX_QUANTILES(los_days, 100) AS q
  FROM cohort
  GROUP BY death_status
)
SELECT
  c.death_status,
  COUNT(*) AS admissions,
  (SELECT d.q[OFFSET(50)] FROM quantiles d WHERE d.death_status = c.death_status) AS p50,
  (SELECT d.q[OFFSET(75)] FROM quantiles d WHERE d.death_status = c.death_status) AS p75,
  (SELECT d.q[OFFSET(90)] FROM quantiles d WHERE d.death_status = c.death_status) AS p90,
  (SELECT d.q[OFFSET(95)] FROM quantiles d WHERE d.death_status = c.death_status) AS p95,
  100.0 * SUM(CASE WHEN c.los_days <= 10.0 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS ten_day_los_rank
FROM cohort AS c
GROUP BY c.death_status
ORDER BY c.death_status;