WITH cases AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 74 AND 84
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
          OR (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
        )
    )
),

controls AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 74 AND 84
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
          OR (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
        )
    )
),

cases_lab AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT l.itemid) AS abnormal_lab_count
  FROM
    cases c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR
  WHERE
    l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY
    c.hadm_id
),

controls_lab AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT l.itemid) AS abnormal_lab_count
  FROM
    controls c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR
  WHERE
    l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
  GROUP BY
    c.hadm_id
),

cases_with_lab AS (
  SELECT
    c.*,
    COALESCE(cl.abnormal_lab_count, 0) AS abnormal_lab_count
  FROM
    cases c
  LEFT JOIN
    cases_lab cl
    ON c.hadm_id = cl.hadm_id
),

controls_with_lab AS (
  SELECT
    c.*,
    COALESCE(cl.abnormal_lab_count, 0) AS abnormal_lab_count
  FROM
    controls c
  LEFT JOIN
    controls_lab cl
    ON c.hadm_id = cl.hadm_id
),

cases_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY abnormal_lab_count) AS quintile
  FROM
    cases_with_lab
)

SELECT
  quintile,
  AVG(hospital_expire_flag) AS mortality,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS mean_los,
  NULL AS comparison_group,
  NULL AS avg_abnormal_labs
FROM
  cases_quintiles
GROUP BY
  quintile

UNION ALL

SELECT
  NULL,
  NULL,
  NULL,
  'cases',
  AVG(abnormal_lab_count)
FROM
  cases_with_lab

UNION ALL

SELECT
  NULL,
  NULL,
  NULL,
  'controls',
  AVG(abnormal_lab_count)
FROM
  controls_with_lab;