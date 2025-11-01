WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '415.1%')
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I26'))
    )
),

meds_first24 AS (
  SELECT
    e.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN
    cohort c
  ON
    e.hadm_id = c.hadm_id
  WHERE
    e.charttime IS NOT NULL
    AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    AND e.medication IS NOT NULL
  GROUP BY
    e.hadm_id
),

readmissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

readmit_flag AS (
  SELECT
    hadm_id,
    CASE
      WHEN DATETIME_DIFF(admittime, prev_dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS is_30day_readmit
  FROM
    readmissions
),

combined AS (
  SELECT
    c.hadm_id,
    c.los_days,
    c.hospital_expire_flag,
    COALESCE(r.is_30day_readmit, 0) AS is_30day_readmit,
    COALESCE(m.med_count, 0) AS med_count
  FROM
    cohort c
  LEFT JOIN
    meds_first24 m
  ON
    c.hadm_id = m.hadm_id
  LEFT JOIN
    readmit_flag r
  ON
    c.hadm_id = r.hadm_id
),

tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS med_tertile
  FROM
    combined
)

SELECT
  med_tertile,
  COUNT(*) AS admissions,
  MIN(med_count) AS min_med_count,
  MAX(med_count) AS max_med_count,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(is_30day_readmit) * 100 AS readmit_30day_percent
FROM
  tertiles
GROUP BY
  med_tertile
ORDER BY
  med_tertile;