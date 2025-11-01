WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%transplant%'
    )
),

meds AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    c.hadm_id = e.hadm_id
  WHERE
    e.charttime >= c.admittime
    AND e.charttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    c.hadm_id

  UNION ALL

  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= c.admittime
    AND pr.starttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY
    c.hadm_id
),

meds_combined AS (
  SELECT
    hadm_id,
    SUM(med_count) AS med_complexity_score
  FROM
    meds
  GROUP BY
    hadm_id
),

cohort_with_score AS (
  SELECT
    c.*,
    COALESCE(m.med_complexity_score, 0) AS med_complexity_score
  FROM
    cohort c
  LEFT JOIN
    meds_combined m
  ON
    c.hadm_id = m.hadm_id
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_complexity_score) AS score_quartile
  FROM
    cohort_with_score
),

readmissions AS (
  SELECT
    q1.hadm_id,
    CASE
      WHEN q2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_30
  FROM
    quartiles q1
  LEFT JOIN
    quartiles q2
  ON
    q1.subject_id = q2.subject_id
    AND q2.admittime > q1.dischtime
    AND q2.admittime <= DATETIME_ADD(q1.dischtime, INTERVAL 30 DAY)
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY q1.hadm_id ORDER BY q2.admittime) = 1
),

final_data AS (
  SELECT
    q.*,
    COALESCE(r.readmit_30, 0) AS readmit_30
  FROM
    quartiles q
  LEFT JOIN
    readmissions r
  ON
    q.hadm_id = r.hadm_id
)

SELECT
  score_quartile,
  COUNT(*) AS n,
  AVG(med_complexity_score) AS mean_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS in_hosp_mortality,
  AVG(readmit_30) AS readmit_30_rate
FROM
  final_data
GROUP BY
  score_quartile
ORDER BY
  score_quartile;