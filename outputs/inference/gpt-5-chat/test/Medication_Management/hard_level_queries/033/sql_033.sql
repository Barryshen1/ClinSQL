WITH sepsis_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(d.long_title) LIKE '%sepsis%'
),
meds_24h AS (
  SELECT sc.subject_id, sc.hadm_id, LOWER(pr.drug) AS drug
  FROM sepsis_cohort sc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON sc.subject_id = pr.subject_id AND sc.hadm_id = pr.hadm_id
  WHERE pr.starttime BETWEEN sc.admittime AND DATETIME_ADD(sc.admittime, INTERVAL 24 HOUR)
),
complexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS complexity_score,
    MAX(CASE WHEN drug LIKE '%amiodarone%' OR drug LIKE '%haloperidol%' OR drug LIKE '%levofloxacin%' THEN 1 ELSE 0 END) AS qt_flag,
    MAX(CASE WHEN drug LIKE '%warfarin%' OR drug LIKE '%heparin%' OR drug LIKE '%aspirin%' OR drug LIKE '%clopidogrel%' THEN 1 ELSE 0 END) AS bleed_flag
  FROM meds_24h
  GROUP BY subject_id, hadm_id
),
flags AS (
  SELECT *,
    CASE WHEN qt_flag = 1 AND bleed_flag = 1 THEN 1 ELSE 0 END AS both_flag
  FROM complexity
),
ranks AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.complexity_score,
    f.both_flag,
    PERCENT_RANK() OVER (ORDER BY f.complexity_score) AS complexity_percentile
  FROM flags f
)
SELECT
  r.subject_id,
  r.hadm_id,
  r.complexity_score,
  r.complexity_percentile,
  r.both_flag,
  sc.anchor_age,
  sc.gender,
  DATETIME_DIFF(sc.dischtime, sc.admittime, DAY) AS los_days,
  sc.hospital_expire_flag
FROM ranks r
JOIN sepsis_cohort sc
  ON r.subject_id = sc.subject_id AND r.hadm_id = sc.hadm_id
WHERE r.complexity_percentile >= 0.75
ORDER BY r.complexity_percentile DESC;