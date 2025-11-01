WITH target_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND LOWER(d.long_title) LIKE '%hemorrhag%'
    AND LOWER(d.long_title) LIKE '%stroke%'
  GROUP BY
    a.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
),
lab_crit AS (
  SELECT
    t.hadm_id,
    di.category
  FROM
    target_adm AS t
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
      ON t.hadm_id = l.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
      ON l.itemid = di.itemid
  WHERE
    l.charttime BETWEEN t.admittime
      AND TIMESTAMP_ADD(t.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND (
      l.valuenum < l.ref_range_lower
      OR l.valuenum > l.ref_range_upper
    )
  GROUP BY
    t.hadm_id,
    di.category
),
scores AS (
  SELECT
    t.*,
    COALESCE(c.crit_sys_count, 0) AS score
  FROM
    target_adm AS t
    LEFT JOIN (
      SELECT
        hadm_id,
        COUNT(DISTINCT category) AS crit_sys_count
      FROM lab_crit
      GROUP BY hadm_id
    ) AS c
      ON t.hadm_id = c.hadm_id
),
p90 AS (
  SELECT
    APPROX_QUANTILES(score, 100)[OFFSET(90)] AS p90_score
  FROM
    scores
),
scored AS (
  SELECT
    s.*,
    p.p90_score,
    CASE
      WHEN s.score >= p.p90_score THEN 'High (≥P90)'
      ELSE 'Low (<P90)'
    END AS instability_group
  FROM
    scores AS s
    CROSS JOIN p90 AS p
)
SELECT
  instability_group,
  COUNT(*) AS n_patients,
  100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_percent,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los_days,
  AVG(score) AS avg_crit_lab_systems_per_patient
FROM
  scored
GROUP BY
  instability_group
ORDER BY
  instability_group DESC;