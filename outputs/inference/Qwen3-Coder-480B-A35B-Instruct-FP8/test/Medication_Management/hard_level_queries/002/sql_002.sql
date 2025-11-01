WITH amipatients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
      ON a.hadm_id = i.hadm_id
  WHERE
    LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
),

first_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    stay_id,
    intime,
    outtime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM amipatients
),

first24hr_meds AS (
  SELECT
    f.hadm_id,
    COUNT(DISTINCT iv.itemid) AS med_complexity_score
  FROM
    first_icu_stays f
  JOIN
    physionet-data.mimiciv_3_1_icu.inputevents iv
      ON f.stay_id = iv.stay_id
  WHERE
    iv.starttime >= f.intime
    AND iv.starttime <= DATETIME_ADD(f.intime, INTERVAL 1 DAY)
  GROUP BY
    f.hadm_id
),

admission_metrics AS (
  SELECT
    f.hadm_id,
    f.subject_id,
    f.intime,
    f.outtime,
    DATETIME_DIFF(f.outtime, f.intime, HOUR) / 24.0 AS icu_los_days,
    f.hospital_expire_flag,
    m.med_complexity_score,
    -- 30-day readmission
    CASE
      WHEN lead_admit.admittime IS NOT NULL
        AND DATETIME_DIFF(lead_admit.admittime, f.dischtime, DAY) BETWEEN 0 AND 30
        AND lead_admit.hospital_expire_flag != 1 THEN 1
      ELSE 0
    END AS readmit_30_days
  FROM
    first_icu_stays f
  JOIN
    first24hr_meds m
      ON f.hadm_id = m.hadm_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.admissions lead_admit
      ON f.subject_id = lead_admit.subject_id
      AND lead_admit.admittime > f.dischtime
      AND lead_admit.hospital_expire_flag != 1
  WHERE
    f.rn = 1
),

tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_complexity_score) AS tertile
  FROM admission_metrics
)

SELECT
  tertile,
  COUNT(*) AS admission_count,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  AVG(med_complexity_score) AS mean_score,
  AVG(icu_los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hosp_mortality_pct,
  AVG(CAST(readmit_30_days AS FLOAT64)) * 100 AS readmit_30d_pct
FROM tertiles
GROUP BY tertile
ORDER BY tertile;