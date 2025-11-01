WITH copd_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND LOWER(dicd.long_title) LIKE '%copd%'
    AND LOWER(dicd.long_title) LIKE '%exacerbation%'
),

med_complexity AS (
  SELECT
    ca.hadm_id,
    COUNT(DISTINCT pr.drug) AS medication_complexity_score
  FROM copd_admissions ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ca.hadm_id = pr.hadm_id
    AND pr.starttime >= ca.admittime
    AND pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
  GROUP BY ca.hadm_id
),

los_mortality AS (
  SELECT
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    hospital_expire_flag
  FROM copd_admissions
),

readmission_30d AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmission_30d_flag
  FROM copd_admissions a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
  WHERE a2.hadm_id IS NOT NULL
    OR a2.hadm_id IS NULL
),

combined AS (
  SELECT
    ca.hadm_id,
    mc.medication_complexity_score,
    lm.los_days,
    lm.hospital_expire_flag,
    COALESCE(r.readmission_30d_flag, 0) AS readmission_30d_flag,
    NTILE(3) OVER (ORDER BY mc.medication_complexity_score) AS tertile
  FROM copd_admissions ca
  LEFT JOIN med_complexity mc ON ca.hadm_id = mc.hadm_id
  LEFT JOIN los_mortality lm ON ca.hadm_id = lm.hadm_id
  LEFT JOIN readmission_30d r ON ca.hadm_id = r.hadm_id
)

SELECT
  tertile,
  COUNT(*) AS n,
  MIN(medication_complexity_score) AS min_complexity,
  MAX(medication_complexity_score) AS max_complexity,
  AVG(medication_complexity_score) AS mean_complexity,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  AVG(readmission_30d_flag) * 100 AS readmission_30d_percent
FROM combined
GROUP BY tertile
ORDER BY tertile;