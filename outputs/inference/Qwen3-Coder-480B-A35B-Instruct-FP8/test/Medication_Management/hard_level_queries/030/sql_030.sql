WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
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
    AND p.anchor_age BETWEEN 71 AND 81
    AND (
      (d.icd_version = 9 AND d.icd_code = '5770')
      OR
      (d.icd_version = 10 AND dd.long_title LIKE '%acute pancreatitis%')
    )
),

meds_72hr AS (
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
    e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    e.hadm_id
),

cohort_with_meds AS (
  SELECT
    c.*,
    COALESCE(m.med_count, 0) AS med_count
  FROM
    cohort c
  LEFT JOIN
    meds_72hr m
  ON
    c.hadm_id = m.hadm_id
),

tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS med_tertile
  FROM
    cohort_with_meds
),

readmissions AS (
  SELECT
    subject_id,
    admittime,
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admit_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

cohort_with_readmit AS (
  SELECT
    t.*,
    CASE
      WHEN r.next_admit_time IS NOT NULL
        AND DATETIME_DIFF(r.next_admit_time, t.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmit_30_days
  FROM
    tertiles t
  JOIN
    readmissions r
  ON
    t.subject_id = r.subject_id AND t.admittime = r.admittime
)

SELECT
  med_tertile,
  COUNT(*) AS patient_count,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS in_hosp_mortality_rate,
  AVG(readmit_30_days) AS readmit_30_days_rate
FROM
  cohort_with_readmit
GROUP BY
  med_tertile
ORDER BY
  med_tertile;