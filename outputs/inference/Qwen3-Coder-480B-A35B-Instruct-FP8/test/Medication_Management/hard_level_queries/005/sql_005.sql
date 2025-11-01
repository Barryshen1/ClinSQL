WITH hepatic_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('570', '5722'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^K72\.(0|1|9)'))
    )
),

first_icu_stay AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM
    hepatic_cohort
),

cohort_first_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    los_days
  FROM
    first_icu_stay
  WHERE
    rn = 1
),

meds_first_72h AS (
  SELECT
    hc.subject_id,
    hc.hadm_id,
    COUNT(DISTINCT e.medication) AS med_complexity_score
  FROM
    cohort_first_stay hc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  ON
    hc.hadm_id = e.hadm_id
  WHERE
    e.charttime >= hc.intime
    AND e.charttime <= DATETIME_ADD(hc.intime, INTERVAL 72 HOUR)
  GROUP BY
    hc.subject_id, hc.hadm_id
),

readmission_raw AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    a1.dischtime,
    a2.admittime AS next_admittime
  FROM
    cohort_first_stay a1
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
  ON
    a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
),

next_admission AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY next_admittime) AS rn
  FROM
    readmission_raw
),

readmission AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN next_admittime IS NOT NULL
        AND DATE_DIFF(next_admittime, dischtime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS readmit_30d
  FROM
    next_admission
  WHERE
    rn = 1
),

final_data AS (
  SELECT
    hc.subject_id,
    hc.hadm_id,
    hc.los_days,
    hc.hospital_expire_flag,
    COALESCE(r.readmit_30d, 0) AS readmit_30d,
    COALESCE(m.med_complexity_score, 0) AS med_complexity_score
  FROM
    cohort_first_stay hc
  LEFT JOIN
    meds_first_72h m
  ON
    hc.hadm_id = m.hadm_id
  LEFT JOIN
    readmission r
  ON
    hc.hadm_id = r.hadm_id
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS score_quintile
  FROM
    final_data
)

SELECT
  score_quintile,
  COUNT(*) AS n,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  AVG(med_complexity_score) AS mean_score,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmit_30d) * 100 AS readmit_30d_pct
FROM
  quintiles
GROUP BY
  score_quintile
ORDER BY
  score_quintile;