WITH admissions_filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

admissions_categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Died in Hospital'
      WHEN discharge_location LIKE '%HOME%' THEN 'Discharged Home'
      ELSE 'Discharged to Facility'
    END AS discharge_group
  FROM
    admissions_filtered
),

grouped_stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS total_admissions,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS count_los_ge_7,
    AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0.0 END) AS prop_los_ge_7,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
  FROM
    admissions_categorized
  GROUP BY
    discharge_group
),

los_percentile AS (
  SELECT
    discharge_group,
    los_days,
    PERCENT_RANK() OVER (PARTITION BY discharge_group ORDER BY los_days) AS percentile_rank
  FROM
    admissions_categorized
)

SELECT
  gs.discharge_group,
  gs.total_admissions,
  gs.count_los_ge_7,
  gs.prop_los_ge_7,
  gs.median_los,
  MIN(lp.percentile_rank) AS percentile_rank_7_days
FROM
  grouped_stats gs
LEFT JOIN
  los_percentile lp
ON
  gs.discharge_group = lp.discharge_group
  AND lp.los_days = 7
GROUP BY
  gs.discharge_group,
  gs.total_admissions,
  gs.count_los_ge_7,
  gs.prop_los_ge_7,
  gs.median_los
ORDER BY
  gs.discharge_group;