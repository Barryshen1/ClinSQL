WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los AS icu_los,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime
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
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_location = 'POSTOPERATIVE'
    AND i.intime >= a.admittime
    AND i.outtime <= a.dischtime
),

first_icu AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_los,
    hospital_expire_flag,
    admittime,
    dischtime,
    icu_intime,
    icu_outtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY icu_intime) AS rn
  FROM
    cohort
),

med_complexity AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.icu_los,
    f.hospital_expire_flag,
    f.admittime,
    f.dischtime,
    f.icu_intime,
    f.icu_outtime,
    COUNT(DISTINCT iv.itemid) AS med_complexity_count
  FROM
    first_icu f
  JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` iv
  ON
    f.stay_id = iv.stay_id
    AND iv.starttime >= f.icu_intime
    AND iv.starttime <= DATETIME_ADD(f.icu_intime, INTERVAL 72 HOUR)
  WHERE
    f.rn = 1
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id, f.icu_los, f.hospital_expire_flag,
    f.admittime, f.dischtime, f.icu_intime, f.icu_outtime
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY med_complexity_count) AS complexity_quintile
  FROM
    med_complexity
),

readmissions AS (
  SELECT
    q.*,
    LEAD(q.admittime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime) AS next_admittime
  FROM
    quintiles q
),

thirty_day_readmit AS (
  SELECT
    *,
    CASE
      WHEN next_admittime IS NOT NULL
        AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmit_30_days
  FROM
    readmissions
),

summary_stats AS (
  SELECT
    complexity_quintile,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(readmit_30_days) AS readmit_30_rate
  FROM
    thirty_day_readmit
  GROUP BY
    complexity_quintile
),

target_patient AS (
  SELECT
    t.complexity_quintile,
    t.icu_los,
    t.hospital_expire_flag,
    t.readmit_30_days
  FROM
    thirty_day_readmit t
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    t.subject_id = p.subject_id
  WHERE
    p.anchor_age = 42
)

SELECT
  s.*,
  t.icu_los AS target_icu_los,
  t.hospital_expire_flag AS target_mortality,
  t.readmit_30_days AS target_readmit
FROM
  summary_stats s
LEFT JOIN
  target_patient t
ON
  s.complexity_quintile = t.complexity_quintile
ORDER BY
  s.complexity_quintile;