WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.subject_id = dx.subject_id AND a.hadm_id = dx.hadm_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 71 AND 81
    AND (
      (dx.icd_version = 9  AND dx.icd_code = '518.82') OR
      (dx.icd_version = 10 AND dx.icd_code = 'J80')
    )
),
instability_per_admission AS (
  SELECT
    ea.hadm_id,
    COALESCE(SUM(
      CASE
        WHEN le.valuenum IS NOT NULL AND (
             (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower) OR
             (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
        THEN 1
        ELSE 0
      END
    ), 0) AS instability_score
  FROM eligible_admissions AS ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = ea.subject_id
   AND le.hadm_id = ea.hadm_id
   AND le.charttime >= ea.admittime
   AND le.charttime < TIMESTAMP_ADD(ea.admittime, INTERVAL 72 HOUR)
  GROUP BY ea.hadm_id
),
admission_info AS (
  SELECT
    ei.hadm_id,
    ei.subject_id,
    ei.admittime,
    ei.dischtime,
    ei.hospital_expire_flag,
    TIMESTAMP_DIFF(ei.dischtime, ei.admittime, SECOND) / 86400.0 AS los_days
  FROM eligible_admissions AS ei
),
critical_lab_flag AS (
  SELECT
    ei.hadm_id,
    MAX(
      CASE
        WHEN le.valuenum IS NOT NULL AND (
             (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower) OR
             (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
        THEN 1 ELSE 0
      END
    ) AS has_crit_lab
  FROM eligible_admissions AS ei
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = ei.subject_id
   AND le.hadm_id = ei.hadm_id
   AND le.charttime >= ei.admittime
   AND le.charttime < TIMESTAMP_ADD(ei.admittime, INTERVAL 72 HOUR)
  GROUP BY ei.hadm_id
),
threshold_p90 AS (
  -- Compute the 90th percentile of instability_score across eligible admissions
  SELECT quantiles[OFFSET(90)] AS p90
  FROM (
    SELECT APPROX_QUANTILES(ip.instability_score, 100) AS quantiles
    FROM instability_per_admission AS ip
  ) AS t
)
SELECT
  CASE
    WHEN ip.instability_score >= t.p90 THEN 'High instability (>= 90th percentile)'
    ELSE 'General (below 90th percentile)'
  END AS group_label,
  AVG(CAST(ai.hospital_expire_flag AS INT64)) AS mortality_rate,
  AVG(ai.los_days) AS mean_los_days,
  AVG(cl.has_crit_lab) AS mean_critical_lab_rate,
  t.p90 AS instability_p90
FROM instability_per_admission AS ip
JOIN admission_info AS ai
  ON ip.hadm_id = ai.hadm_id
JOIN critical_lab_flag AS cl
  ON ip.hadm_id = cl.hadm_id
CROSS JOIN threshold_p90 AS t
GROUP BY group_label, t.p90
ORDER BY group_label;