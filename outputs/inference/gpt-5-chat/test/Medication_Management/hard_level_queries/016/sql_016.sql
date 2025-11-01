WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND LOWER(dd.long_title) LIKE '%hepatic failure%'
),
med_complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT COALESCE(p.formulary_drug_cd, p.drug)) AS complexity_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime >= c.admittime
    AND p.starttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.hadm_id
),
los_mortality_readmit AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.hospital_expire_flag,
    -- 30-day readmission: check if any future admission within 30 days
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm2
      WHERE adm2.subject_id = c.subject_id
        AND adm2.admittime > c.dischtime
        AND adm2.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_30d
  FROM cohort c
),
combined AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.complexity_score,
    l.los_days,
    l.hospital_expire_flag,
    l.readmit_30d
  FROM med_complexity m
  JOIN los_mortality_readmit l
    ON m.subject_id = l.subject_id AND m.hadm_id = l.hadm_id
),
tertiles AS (
  SELECT
    subject_id,
    hadm_id,
    complexity_score,
    los_days,
    hospital_expire_flag,
    readmit_30d,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM combined
)
SELECT
  tertile,
  COUNT(DISTINCT hadm_id) AS admissions,
  AVG(complexity_score) AS avg_complexity_score,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS in_hosp_mortality_rate,
  AVG(readmit_30d) AS readmit_30d_rate
FROM tertiles
GROUP BY tertile
ORDER BY tertile;