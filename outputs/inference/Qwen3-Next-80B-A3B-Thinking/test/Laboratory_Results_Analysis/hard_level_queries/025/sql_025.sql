WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
),

lab_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT l.itemid) AS lab_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY
    c.subject_id, c.hadm_id
),

percentile AS (
  SELECT
    PERCENTILE_CONT(lab_score, 0.9) OVER () AS p90
  FROM
    lab_scores
),

risk_groups AS (
  SELECT
    ls.subject_id,
    ls.hadm_id,
    ls.lab_score,
    CASE WHEN ls.lab_score >= p.p90 THEN 'high-risk' ELSE 'low-risk' END AS risk_group
  FROM
    lab_scores ls
  CROSS JOIN
    percentile p
)

SELECT
  risk_group,
  SUM(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS mortality_percent,
  AVG(DATE_DIFF(c.dischtime, c.admittime, DAY)) AS mean_los,
  AVG(rg.lab_score) AS avg_critical_labs
FROM
  risk_groups rg
JOIN
  cohort c
  ON rg.subject_id = c.subject_id AND rg.hadm_id = c.hadm_id
GROUP BY
  risk_group;