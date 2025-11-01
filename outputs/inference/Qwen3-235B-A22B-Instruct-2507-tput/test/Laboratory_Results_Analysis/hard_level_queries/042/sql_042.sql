WITH patients_age AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE
    gender = 'M'
),
admissions_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN
    patients_age p
  ON
    a.subject_id = p.subject_id
  WHERE
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
),
ich_codes AS (
  SELECT
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE
    icd_version = 10
    AND icd_code LIKE 'I61%'
),
ich_admissions AS (
  SELECT
    da.subject_id,
    da.hadm_id,
    da.admittime,
    da.dischtime,
    da.hospital_expire_flag,
    DATETIME_DIFF(da.dischtime, da.admittime, HOUR) / 24.0 AS los_days
  FROM
    admissions_age da
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    da.hadm_id = di.hadm_id
  JOIN
    ich_codes ic
  ON
    di.icd_code = ic.icd_code
  WHERE
    di.icd_version = 10
),
abnormal_labs_48h AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN
    ich_admissions ia
  ON
    le.hadm_id = ia.hadm_id
  WHERE
    le.charttime >= ia.admittime
    AND le.charttime <= DATETIME_ADD(ia.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
),
instability_score AS (
  SELECT
    subject_id,
    COUNT(DISTINCT itemid) AS instability_count
  FROM
    abnormal_labs_48h
  GROUP BY
    subject_id
),
quartiles AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.los_days,
    ia.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY iss.instability_count) AS instability_quartile
  FROM
    ich_admissions ia
  JOIN
    instability_score iss
  ON
    ia.subject_id = iss.subject_id
)
SELECT
  instability_quartile AS quartile,
  COUNT(*) AS patient_count,
  AVG(los_days) AS mean_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  quartiles
GROUP BY
  instability_quartile
ORDER BY
  quartile;