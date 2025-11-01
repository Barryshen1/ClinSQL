WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admittime = (
      SELECT MIN(admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = p.subject_id
    )
),

hemorrhagic_stroke AS (
  SELECT DISTINCT
    c.*
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    c.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(d.icd_code, r'^I61|^I60')
),

meds_first_7d AS (
  SELECT
    hs.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drugs
  FROM
    hemorrhagic_stroke hs
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    hs.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= hs.admittime
    AND pr.starttime <= DATETIME_ADD(hs.admittime, INTERVAL 7 DAY)
  GROUP BY
    hs.hadm_id
),

meds_filled AS (
  SELECT
    hs.*,
    COALESCE(m.unique_drugs, 0) AS unique_drugs
  FROM
    hemorrhagic_stroke hs
  LEFT JOIN
    meds_first_7d m
  ON
    hs.hadm_id = m.hadm_id
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY unique_drugs) AS med_quintile
  FROM
    meds_filled
),

readmissions AS (
  SELECT
    q.*,
    CASE
      WHEN a2.admittime IS NOT NULL
        AND a2.admittime < DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    quintiles q
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
  ON
    q.subject_id = a2.subject_id
    AND a2.admittime > q.dischtime
    AND a2.admittime < DATETIME_ADD(q.dischtime, INTERVAL 30 DAY)
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY q.hadm_id ORDER BY a2.admittime) = 1
)

SELECT
  med_quintile,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS inpatient_mortality,
  AVG(readmit_30d) AS readmit_30d_rate
FROM
  readmissions
GROUP BY
  med_quintile
ORDER BY
  med_quintile;